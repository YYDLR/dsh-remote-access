param([string]$SessionDir = '')

# dsh-lock-probe.ps1 -- answer "is this session's write lock currently held?"
#
# Why this works: on Windows dsh guards a session with a NAMED KERNEL SEMAPHORE
# (no filesystem footprint). Name, straight from the source
# (dsh-session-persistence-jsonl/lib/index.js -> acquireLockHandleWin32):
#
#   Local\dsh-session-lock-<sha256( lowercased absolute path of "<dir>\session.lock" )>
#
# created with initial count 1 / max 1, acquired via WaitForSingleObject(handle, 0).
# The object is destroyed when its last handle closes, so its mere existence
# means somebody is holding the lock right now.
#
# CRITICAL: the "Local\" namespace is per Windows LOGON SESSION. A probe run over
# SSH lands in session 0 and would always report "free" (false negative). It must
# run in the SAME session as dsh -- see the scheduled-task recipe below.
#
# Run it from session 1:
#   schtasks /create /tn dsh-lock-probe /tr "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\<you>\dsh-lock-probe.ps1" /sc once /st 00:00 /f /it
#   schtasks /run /tn dsh-lock-probe
#   type %USERPROFILE%\lock-probe.txt
#   schtasks /delete /tn dsh-lock-probe /f

$ErrorActionPreference = 'Stop'

$out = Join-Path $env:USERPROFILE 'lock-probe.txt'
$sessions = Join-Path $env:USERPROFILE '.dsh\sessions'

if (-not $SessionDir) {
    $f = Get-ChildItem $sessions -Recurse -Filter 'session.v4.jsonl.zstd' -ErrorAction SilentlyContinue |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $f) { throw "no session archive found under $sessions" }
    $SessionDir = $f.Directory.FullName
}

$lockPath = Join-Path $SessionDir 'session.lock'
$sha = [System.Security.Cryptography.SHA256]::Create()
$hash = ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($lockPath.ToLowerInvariant())) | ForEach-Object { $_.ToString('x2') }) -join ''
$sessionLockName = 'Local\dsh-session-lock-' + $hash

$L = @()
$L += 'pid=' + $PID
$L += 'sessionId=' + (Get-Process -Id $PID).SessionId
$L += 'sessionDir=' + $SessionDir
$L += 'lockPath=' + $lockPath
$L += 'semaphoreName=' + $sessionLockName

# SANITY CHECK (NOT proof of the name): the guard holds this mutex for its whole
# lifetime, so the probe must be able to see it. This only proves "I can open an
# existing kernel object in this session" -- it does NOT prove the session-lock
# name was derived correctly. Only a HELD/FREE pair does that (see guide 7-5).
$guardName = 'Local\dsh-web-guard'
$L += ''
$L += '### SANITY (must be EXISTS): guard mutex -- proves nothing about the name below'
try {
    $m = [System.Threading.Mutex]::OpenExisting($guardName)
    $got = $m.WaitOne(0)
    $L += "mutex $guardName => EXISTS, acquired=$got (guard is holding it)"
    if ($got) { $m.ReleaseMutex() }
    $m.Dispose()
} catch {
    $L += "mutex $guardName => NOT FOUND ($($_.Exception.GetType().Name)) -- DO NOT TRUST the result below"
}

$L += ''
$L += '### TARGET: session write-lock semaphore'
try {
    $s = [System.Threading.Semaphore]::OpenExisting($sessionLockName)
    $L += 'semaphore => EXISTS  => LOCK IS HELD'
    $s.Dispose()
} catch [System.Threading.WaitHandleCannotBeOpenedException] {
    $L += 'semaphore => NOT FOUND  => LOCK IS FREE (nobody holds it)'
} catch {
    $L += 'UNKNOWN: object may exist but cannot be opened (' + $_.Exception.GetType().Name + ') -- do NOT treat as FREE'
}

$L | Out-File -Encoding utf8 $out
Get-Content $out
