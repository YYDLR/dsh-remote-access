# dsh-web-guard.ps1  (v6)
#
# Purpose: keep dsh web running, and RESTART it after the client is done, so the
#          cross-process session write-lock gets released.
#
# Idle rule: no TCP connection AND the tracked session file quiet for 5 min;
#            both held for 15 min  ->  kill & restart.
#            If NO session file has ever been tracked, this process cannot hold
#            any lock, so the idle timer stays OFF and it simply stands by.
#
# v2: heartbeat log every 10 min.
# v3: (1) single-instance guard via named mutex
#     (2) exponential backoff when startup keeps failing
#     (3) a run shorter than 60s counts as a failure (crash-loop protection)
# v4: (1) file-quiet test tracks ONLY the session file the phone used, so the
#         desktop app writing OTHER sessions no longer blocks release.
#     (2) log rotation at 5 MB (keeps one previous file as .log.1)
# v5: (1) FIX: when no session file has ever been tracked, never count idle and
#         never restart. Before this, an idle guard killed and restarted dsh web
#         every ~15 min forever -- a new token each time, a ~10 s outage window,
#         and an ever-growing dshweb.log -- all for nothing, because a process
#         that never opened a session cannot be holding the lock.
#     (2) FIX: quote the start-bat path. PowerShell joins -ArgumentList with
#         spaces and adds no quoting of its own, so with a space in the profile
#         ("C:\Users\John Doe") cmd looked for a truncated path and the bat
#         NEVER ran -- silently.
#     (3) port / connection regexes anchored to the local-address column, so
#         ":3081" can no longer match a remote address or ":30810".
#     (4) explicit log line when the sessions directory is missing.
#     (5) rotate dshweb.log too (2 MB), before dsh appends to it.
#     (6) comments are ASCII-only ON PURPOSE: PowerShell 5.1 reads BOM-less
#         UTF-8 as ANSI(GBK) and would garble any non-ASCII text. Keeping the
#         whole file ASCII makes the encoding irrelevant.
# v6: WARN every 30 s (not just once at startup) when a client IS connected but no
#     session file can be found. That is the ONE silent failure where the lock would
#     never be released while the log still looks healthy.

$ErrorActionPreference = 'SilentlyContinue'

# ===== tunables =====
$Port           = 3081
$StartBat       = Join-Path $env:USERPROFILE 'dsh-web-start.bat'
$SessionsDir    = Join-Path $env:USERPROFILE '.dsh\sessions'
$LogFile        = Join-Path $env:USERPROFILE 'dsh-web-guard.log'
$DshLog         = Join-Path $env:USERPROFILE 'dshweb.log'

$CheckSec       = 30      # evaluation interval
$FileIdleSec    = 300     # 5 min: the tracked session file must be quiet this long
$TotalIdleSec   = 900     # 15 min: the two conditions must hold this long
$HeartbeatSec   = 600     # 10 min: "I am alive" line
$StartWaitSec   = 180     # max wait for the port to appear
$ShortRunSec    = 60      # a run shorter than this counts as a failure
$BackoffBase    = 60      # first backoff: 60s
$BackoffMax     = 1800    # backoff ceiling: 30 min
$LogMaxBytes    = 5MB     # rotate the guard log when it grows past this
$DshLogMaxBytes = 2MB     # rotate dshweb.log when it grows past this

function Write-Log([string]$msg) {
    $t = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    try {
        if ((Test-Path $LogFile) -and ((Get-Item $LogFile).Length -gt $LogMaxBytes)) {
            Move-Item -Force $LogFile "$LogFile.1"
        }
        Add-Content -Path $LogFile -Value "[$t] $msg" -ErrorAction Stop
    } catch { }
}

function Get-PortPid([int]$port) {
    # Anchored to the local-address column: ":3081" inside a remote address, or
    # a longer port such as ":30810", can never match.
    $hit = netstat -ano | Select-String "^\s*TCP\s+127\.0\.0\.1:$port\s+\S+\s+LISTENING"
    if (-not $hit) { return $null }
    return ($hit[0].Line -split '\s+')[-1]
}

function Get-ConnCount([int]$port) {
    return (netstat -ano | Select-String "^\s*TCP\s+127\.0\.0\.1:$port\s+\S+\s+ESTABLISHED").Count
}

function Get-NewestSessionPath() {
    $f = Get-ChildItem $SessionsDir -Recurse -Filter '*.zstd' -ErrorAction SilentlyContinue |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($f) { return $f.FullName }
    return $null
}

# ---------------- single instance ----------------
# NB: Local\ only excludes within this login session (see docs section 5.5)
$mutex = New-Object System.Threading.Mutex($false, 'Local\dsh-web-guard')
if (-not $mutex.WaitOne(0)) {
    Write-Log 'another guard instance is already running; exiting'
    exit 0
}

Write-Log '=== guard v6 started (mutex acquired) ==='

if (-not (Test-Path $SessionsDir)) {
    Write-Log "WARN: sessions dir not found: $SessionsDir (lock tracking will stay off)"
}
if (-not (Test-Path $StartBat)) {
    Write-Log "FATAL: start bat not found: $StartBat"
    exit 1
}

$failCount = 0

while ($true) {
    # ---------------- start dsh web ----------------
    # Rotate dsh's own log first: it is appended to with ">>" and has no
    # rotation of its own.
    try {
        if ((Test-Path $DshLog) -and ((Get-Item $DshLog).Length -gt $DshLogMaxBytes)) {
            Move-Item -Force $DshLog "$DshLog.1"
        }
    } catch { }

    # Quote the path. PowerShell joins -ArgumentList with spaces and adds no
    # quoting of its own, so a profile containing a space would make cmd look
    # for a truncated path and never run the bat -- with no visible symptom.
    Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', ('"' + $StartBat + '"') -WindowStyle Hidden | Out-Null
    Write-Log 'launched dsh-web-start.bat; waiting for the port...'

    $waited = 0
    while ($waited -lt $StartWaitSec) {
        Start-Sleep -Seconds 5
        $waited += 5
        if (Get-PortPid $Port) { break }
    }

    if (-not (Get-PortPid $Port)) {
        $failCount++
        $wait = [int][Math]::Min($BackoffBase * [Math]::Pow(2, $failCount - 1), $BackoffMax)
        Write-Log "startup failed after ${StartWaitSec}s (failure #$failCount); backing off ${wait}s"
        Start-Sleep -Seconds $wait
        continue
    }

    Write-Log "dsh web is up on port $Port"
    $runStart = Get-Date

    # ---------------- monitor loop ----------------
    $totalIdle         = 0
    $sinceHeartbeat    = 0
    $activeSessionPath = $null

    while ($true) {
        Start-Sleep -Seconds $CheckSec

        if (-not (Get-PortPid $Port)) {
            Write-Log 'port gone (process exited); restarting'
            break
        }

        $conns = Get-ConnCount $Port

        # While a client is connected, remember which session file is being written.
        if ($conns -gt 0) {
            $p = Get-NewestSessionPath
            if ($p) { $activeSessionPath = $p }
        }

        # File-quiet test: only the remembered file counts. 999999 is a sentinel
        # meaning "no tracked file" and is NOT a huge idle time.
        if ($activeSessionPath -and (Test-Path $activeSessionPath)) {
            $fileIdle = [int]((Get-Date) - (Get-Item $activeSessionPath).LastWriteTime).TotalSeconds
        } else {
            $fileIdle = 999999
        }

        if (-not $activeSessionPath) {
            # ---- v5 standby branch ----
            # Nothing was ever tracked => this process never opened a session =>
            # it cannot be holding the write lock => there is nothing to release.
            # A restart here would only churn the launch token and drop the
            # connection for ~10 s. Stand by and keep the idle timer at zero.
            $active = $false
            if ($totalIdle -ne 0) { $totalIdle = 0 }
            if ($conns -gt 0) {
                Write-Log "WARN: conns=$conns but no session file tracked under $SessionsDir -- lock release will NOT work"
            } else {
                Write-Log "standby: no tracked session yet; idle timer off (conns=$conns)"
            }
        } else {
            $active = ($conns -gt 0 -or $fileIdle -lt $FileIdleSec)

            if ($active) {
                if ($totalIdle -gt 0) {
                    Write-Log "activity detected; idle reset (conns=$conns fileIdle=${fileIdle}s)"
                }
                $totalIdle = 0
            } else {
                $totalIdle += $CheckSec
                Write-Log "idle ${totalIdle}s / ${TotalIdleSec}s (conns=0 fileIdle=${fileIdle}s)"

                if ($totalIdle -ge $TotalIdleSec) {
                    $p = Get-PortPid $Port
                    if ($p) {
                        Write-Log "idle threshold reached; restarting to release the session lock (kill PID $p)"
                        Stop-Process -Id $p -Force
                    }
                    Start-Sleep -Seconds 5
                    break
                }
            }
        }

        # ---- heartbeat: always runs ----
        $sinceHeartbeat += $CheckSec
        if ($sinceHeartbeat -ge $HeartbeatSec) {
            if (-not $activeSessionPath) { $state = 'standby' }
            elseif ($active)             { $state = 'busy' }
            else                         { $state = "idle ${totalIdle}s" }
            Write-Log "heartbeat: alive, conns=$conns, fileIdle=${fileIdle}s, state=$state"
            $sinceHeartbeat = 0
        }
    }

    # ---------------- crash-loop protection ----------------
    $ranSec = [int]((Get-Date) - $runStart).TotalSeconds
    if ($ranSec -lt $ShortRunSec) {
        $failCount++
        $wait = [int][Math]::Min($BackoffBase * [Math]::Pow(2, $failCount - 1), $BackoffMax)
        Write-Log "short-lived run (${ranSec}s, failure #$failCount); backing off ${wait}s"
        Start-Sleep -Seconds $wait
    } else {
        if ($failCount -gt 0) { Write-Log "stable run (${ranSec}s); failure counter reset" }
        $failCount = 0
    }
}
