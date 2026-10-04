# 手机远程使用电脑 DSH —— 完整复现指南

> **本文档的目标**：让一个**完全不知情的人或 AI**，照着它从零搭出
> "人在外面用手机访问家里电脑的 DSH"。全程约 30 分钟（验证"用完释放锁"还要再等约 20 分钟）。

> 📌 **全文编号约定**：**「步骤 N」** = 第 3 节里的部署小步；**「第 N 节」** = 顶层章节。
> **特别注意：「第 6 节」= 故障排查，不是「步骤 6 · 发布到 tailnet」。**

> **适用环境**：Windows 10/11 · DeepSeek Harness 桌面版（`0.2.0-rc.2` 或更高）· Tailscale
> ⚠️ **本方案只针对并实测于 DSH** —— 会话写锁的行为、`--trusted-host`、profile 机制等都是 DSH 特有的，
> **未在其他 AI 工具上验证过**。换工具的话，第 5 节那套"为什么必须用完重启"的推理需要重新确认。
> **目标**：人在外面时用手机 ① 打开电脑上的 DSH ② （可选）让手机上的 AI 代你操作电脑
> **阅读方式**：从头按顺序做。所有脚本命令都可直接复制；需要你替换的占位符**汇总在第 4 节**（**不止 3 个**，请对着表逐个换掉）。

---

## TL;DR（全程约 30 分钟）

```
① 装 Tailscale（电脑 + 手机，同账号）
② 写 2 个脚本 dsh-web-start.bat / dsh-web-guard.ps1
③ 建 2 个计划任务（登录启动 + 每 5 分钟保活）
④ tailscale serve --bg 3081
⑤ 手机打开 https://<设备>.<tailnet>.ts.net/
```
验证"用完能释放锁"还要**再等最长约 20 分钟**（见步骤 7③）。

> ⚠️ **先理解一句话**：本方案**不是"用完即释放"**，而是一个**最长约 20 分钟的自愈窗口**。
> 手机停止使用后，锁会在 **5 分钟文件静默 + 15 分钟空闲**之后自动释放。急用见第 6 节。

---

## 0 · 你会得到什么

| 场景 | 效果 |
|---|---|
| **人在外面** | 手机浏览器打开 `https://<你的设备>.<你的tailnet>.ts.net/` → 秒开电脑的 DSH，能看会话、能对话 |
| **（可选）让 AI 干活** | 对手机上的 AI 说「在我电脑上看看 D 盘还剩多少」，它通过 SSH 在电脑执行并返回结果 |
| **回家用电脑** | 手机停用后，**最长约 20 分钟**自动释放会话锁；急用可按第 6 节手动 `taskkill` 立即释放 |
| **安全性** | **不向公网暴露任何端口**，全部走 Tailscale 加密隧道（仅 tailnet 内可达） |

---

## 1 · 前置条件与获取

### 1.1 需要什么

| 需要 | 说明 |
|---|---|
| **Windows 10/11 电脑** | 需要**管理员权限**（建计划任务要用） |
| **DeepSeek Harness 桌面版** | 版本 **`0.2.0-rc.2` 或更高**。⚠️ 低于此版本会报 `cannot represent developer message` |
| **Tailscale** | 电脑和手机都要装，**登录同一账号** |
| **手机** | 任意浏览器（Chrome / Safari / 自带浏览器均可） |
| **（可选）OpenSSH 服务端** | 只有需要"让手机上的 AI 操作电脑"才要 |

**怎么查当前 DSH 版本**：用步骤 1.3 找到的 `dsh.cmd` 执行 `--version`，或看桌面版「关于」。

### 1.2 从哪里获取

| 软件 | 获取方式 |
|---|---|
| **DeepSeek Harness 桌面版** | 从**官方渠道**获取（GitHub 仓库 `deepseek-ai/deepseek-harness` 或其官网发布的桌面安装包）。**以官方说明为准**，本指南不提供下载链接 |
| **Tailscale** | `https://tailscale.com/download`，选 Windows / Android / iOS |

### 1.3 找出 DSH 的安装目录

本指南用 `<安装目录>` 指代它。**三种找法，按推荐顺序**：

**方法 A（首选）· 看快捷方式**

> 右键桌面或开始菜单里的 DSH 快捷方式 → **属性** → 看「**目标**」栏 →
> 去掉末尾的 `\DeepSeek Harness.exe`，剩下的就是 `<安装目录>`。

**方法 B · 从运行中的进程反查**

```powershell
# PowerShell（推荐）——避开了新版 Windows 已移除的 wmic
Get-CimInstance Win32_Process -Filter "Name='DeepSeek Harness.exe'" |
  Select-Object -ExpandProperty ExecutablePath
```

> ⚠️ **不要用 `wmic`**：Windows 11 24H2 起它已被默认移除（保留为可选功能），大概率报"不是内部或外部命令"。

**方法 C · 多盘搜索**（兜底，慢）

```bat
:: CMD 交互式用 %d；写进 .bat 文件请写成 %%d
for %d in (C D E F) do @dir /s /b "%d:\*dsh.cmd" 2>nul
```

**验证你找对了**：

```bat
dir "<安装目录>\resources\runtime\cli\bin\dsh.cmd"
```

> ⚠️ **路径不一定是 `resources\runtime\cli\bin\`**——不同桌面版版本/安装方式的层级会变
> （也可能是 `resources\app\runtime\cli\bin\` 等）。
> **如果上面这条报"找不到文件"，就用下面这条在安装目录里搜**：
> ```bat
> dir /s /b "<安装目录>\dsh.cmd"
> ```
> **搜出来的那个 `dsh.cmd` 在哪个目录，就把那个目录填进后面的 `DSH_DIR`。**

### 1.4 前置检查清单（动手前先打勾）

> 📌 **全文编号约定**：**「步骤 N」** = 第 3 节里的部署小步；**「第 N 节」** = 顶层章节。
> **特别注意：「第 6 节」= 故障排查，不是「步骤 6 · 发布到 tailnet」。**

> ⚠️ **检查项 2 —— 确认会话目录真的在这个路径，否则后面会"静默失效"。**
>
> guard 默认盯 `%USERPROFILE%\.dsh\sessions`。若你的 dsh 把会话放在别处，
> guard 会**永远追踪不到会话文件 → 永不重启 → 锁永不释放**，
> 而日志里看起来一切正常（一直 `standby`，被第 5 节判为"健康"）—— **这是全文唯一一处"失败被自己认证为成功"的地方**。
> ```bat
> dir /s /b "%USERPROFILE%\.dsh\sessions\session*.zstd"
> ```
> **有输出 = 路径正确。** 没输出就先找真实位置：
> ```bat
> dir /s /b "%USERPROFILE%\*.zstd" 2>nul
> dir /s /b "<你的 DSH 工作目录>\.dsh\sessions\session*.zstd" 2>nul
> ```
> 找到之后，把 guard 脚本顶部的 `$SessionsDir` 改成实际目录。

> ⚠️ **检查项 3 —— 自动登录（决定"重启之后你还连不连得上"）。**
>
> guard 的计划任务是 `onlogon` 触发。若电脑因 Windows Update / 断电重启后**停在登录界面**，
> 任务**不会触发** → guard 起不来 → **人在外面彻底连不上**，而且现象跟第 6 节任何一条故障都对不上。
>
> 二选一即可：
> - **开自动登录**：`Win+R` → `netplwiz` → 取消勾选"要使用本计算机，用户必须输入用户名和密码"
>   （Win11 若没这一项，看「设置 → 账户 → 登录选项」）。
>   ⚠️ 代价：有物理接触的人开机就能进桌面。
> - **不开**：接受"重启后需要有人登录一次"。**如果你能重启电脑的时候人肯定在电脑前，这就够了。**
>
> **重启后怎么确认 guard 起来了**：等约 3 分钟，然后
> ```bat
> type "%USERPROFILE%\dsh-web-guard.log"
> ```
> 应看到一行新的 `=== guard v6 started (mutex acquired) ===`。

> ⚠️ **检查项 1 —— 最容易被忽略，也最致命：确认这台电脑不会睡眠。**
>
> 本方案的前提是"你人在外面时，电脑还醒着"。Windows 默认 15～30 分钟无操作就睡眠，
> **电脑一睡，Tailscale 立刻断开，手机就是打不开页面**。
> 更要命的是：**第 7 节的验证是在电脑跟前刚点完鼠标做的，必然全绿** ——
> 你会带着"部署成功"的结论出门，然后在外面发现完全连不上，而现象跟第 6 节任何一条故障都对不上。
>
> 用**管理员 CMD** 执行（**是否接受这个取舍由你决定**）：
> ```bat
> rem 插电时（AC）：永不睡眠、永不休眠；屏幕照常 15 分钟关
> powercfg /change standby-timeout-ac 0
> powercfg /change hibernate-timeout-ac 0
> powercfg /change monitor-timeout-ac 15
> rem 用电池时（DC）：同样永不睡眠（笔记本拔电也有效）
> powercfg /change standby-timeout-dc 0
> powercfg /change hibernate-timeout-dc 0
> powercfg /change monitor-timeout-dc 10
> ```
> 笔记本还要单独管合盖：先 `powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0`，再 `powercfg /setactive SCHEME_CURRENT`。
>
> **验证**（只看**当前交流电源**那一项，应为 `0x00000000`）：
> ```bat
> powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE | findstr /i "索引 Index"
> ```
>
> **想还原**：把上面那几条的数值改回你原来的（例如 `powercfg /change standby-timeout-ac 30`）。
> ⚠️ **不要用 `powercfg /restoredefaultschemes`** —— 它会把你这台机器上**所有**自定义电源设置一起清掉，且不可逆。

| ✓ | 检查项 | 怎么确认 |
|---|---|---|
| ☐ | **电脑已用你的账号登录**（不是停在登录界面） | 见步骤 5 的运行前提——**这条关系到数据安全** |
| ☐ | Tailscale 已装且电脑/手机在同一 tailnet | `tailscale status` |
| ☐ | Tailscale 后台已启用 **MagicDNS** 和 **HTTPS Certificates** | 见步骤 6 的前置条件 |
| ☐ | `<安装目录>` 已确认，且找到了 `dsh.cmd` 的实际路径 | 见 1.3 |
| ☐ | 端口 **3081** 未被占用 | `netstat -ano \| findstr :3081`（应无输出） |
| ☐ | 你手上有**管理员**权限 | 能打开"终端(管理员)" |

---

## 2 · 架构与设计要点

```
┌──────────────────┐
│  手机            │
│  ├─ Tailscale    │  加密隧道（点对点）
│  └─ 浏览器        │
└────────┬─────────┘
         │ 仅 tailnet 内可达，公网不可达
         ▼
┌──────────────────────────────────────────┐
│  电脑（Windows，你的登录会话）            │
│                                           │
│   tailscale serve (443, HTTPS)            │
│          ↓                                │
│   127.0.0.1:3081  ← dsh web               │
│          ↑                                │
│   guard 守护脚本（自启 + 保活 + 空闲重启）│
│                                           │
│   sshd (22)  ←（可选）手机 AI 的操作入口   │
└──────────────────────────────────────────┘
```

### 三个必须理解的设计要点

**① dsh web 只绑 `127.0.0.1`**

dsh 明确**拒绝** `--host 0.0.0.0`：

```
error: --host 0.0.0.0 is intentionally not supported yet for safety:
       it would expose remote code execution to the network
```

**这是对的**——对外访问**完全交给 Tailscale**，不要试图改这个参数。

**② 必须加 `--trusted-host`**

不加的话浏览器会**一直显示"重新连接中"**，因为 dsh 会拒绝 Host 不是回环地址的 API 请求。

**③ 会话锁是"进程级"的，必须靠重启释放**

详见**第 5 节**。**建议先读第 5 节再动手**，否则不会理解 guard 为什么这么写。

---

## 3 · 部署步骤

### 步骤 1 · Tailscale 组网

1. 电脑、手机各装 Tailscale，用**同一账号**登录
2. 都设为**开机自启**（安装后默认即是）
3. **记下电脑的 DNS 名**——在 `https://login.tailscale.com/admin/machines` 能看到，形如：

```
<设备名>.<tailnet名>.ts.net
```

**验证**：

```bat
tailscale status
```

应能看到自己和手机都在列表里，状态为 `active`。

### 步骤 2 · （可选）开启 SSH + 让手机上的 AI 接手

> **只想要"手机看电脑 DSH"的话，整步跳过。**

#### 2.1 电脑侧：装并启动 OpenSSH 服务端

**管理员 PowerShell**：

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
```

**验证**：`Get-Service sshd` 应显示 `Running`。

> ⚠️ **先别关密码登录。** 加固要等 **2.4「连通测试成功」之后**再回来做（见 2.4b）。
> 顺序反了、公钥或 ACL 又恰好有问题，你就会**同时失去密码登录这条路**，只能走到电脑前改回来。

#### 2.2 手机侧：生成密钥并取出公钥

**示例（Termux 路线，其他 SSH App 请按其文档导出公钥）**：

```
pkg install openssh
ssh-keygen -t ed25519 -C dsh-phone
cat ~/.ssh/id_ed25519.pub        # 这一整行就是要贴进电脑的内容
```

#### 2.3 电脑侧：把公钥落地（含 ACL 设置）

```bat
if not exist "%USERPROFILE%\.ssh" mkdir "%USERPROFILE%\.ssh"
:: ⚠️【先做这一步】确认 sshd 到底读哪个文件 —— 1.4 要求你用管理员账户，
::   所以下面这条的输出**很可能是 A**，那就别用本代码块里那两条针对用户目录的 icacls
findstr /i /n "AuthorizedKeysFile Match" "%ProgramData%\ssh\sshd_config"
::   A) 有【未注释】的 Match Group administrators
::        -> 【管理员 CMD】把公钥【追加】进去，再收紧权限：
::           type "<公钥文件路径>" >> "%ProgramData%\ssh\administrators_authorized_keys"
::           icacls "%ProgramData%\ssh\administrators_authorized_keys" /inheritance:r /grant "SYSTEM:F" "Administrators:F"
::        ⚠️ 注意是 >>（追加），写 > 会覆盖掉别人原有的公钥
::        ⚠️ %ProgramData%\ssh\ 需要管理员权限，普通窗口会报 Access is denied
::        -> 权限用下方「落点对照表」里那一条，**不要**用本块的 icacls
::   B) 没有（或整段被注释掉）
::        -> 【普通 CMD】把公钥【追加】进去：
::           if not exist "%USERPROFILE%\.ssh" mkdir "%USERPROFILE%\.ssh"
::           type "<公钥文件路径>" >> "%USERPROFILE%\.ssh\authorized_keys"
::           然后继续执行下面的 icacls

:: 【仅 B 的情况】建好 authorized_keys 并粘入公钥（一行一个），然后设置权限：
icacls "%USERPROFILE%\.ssh\authorized_keys" /inheritance:r
:: ⚠️ 微软账户登录时，%USERNAME% 常常**不是**真正的账户名。先用 whoami 确认，
::    再用它输出的整串（形如 计算机名\用户名）替换下面这条里的 %USERDOMAIN%\%USERNAME%
whoami
icacls "%USERPROFILE%\.ssh\authorized_keys" /grant "SYSTEM:F" "Administrators:F" "%USERDOMAIN%\%USERNAME%:F"
```

> ⚠️ **先确认 sshd 到底读哪个文件 —— 管理员账户十有八九不是用户目录那个。**
>
> Windows OpenSSH 的默认 `sshd_config` 末尾通常有一段**启用状态**的：
> ```
> Match Group administrators
>        AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
> ```
> 而本指南要求你用管理员账户（见 1.4），于是 sshd **根本不会去读 `%USERPROFILE%\.ssh\authorized_keys`**。
> 先查一下：
> ```bat
> findstr /i /n "AuthorizedKeysFile Match" "%ProgramData%\ssh\sshd_config"
> ```
>
> | 查到什么 | 公钥该放哪 | 权限怎么给 |
> |---|---|---|
> | 有**未注释**的 `Match Group administrators` | `%ProgramData%\ssh\administrators_authorized_keys` | `icacls "%ProgramData%\ssh\administrators_authorized_keys" /inheritance:r /grant "SYSTEM:F" "Administrators:F"` |
> | 没有（或整段被注释掉） | `%USERPROFILE%\.ssh\authorized_keys` | 见下面那条 ACL 说明 |
>
> ⚠️ **两种落点的"仍然要密码"原因完全不同**：放错文件是**第一个**要排查的；
> 下面那条（ACL / 权限）**只在你确实用用户目录那个文件时才适用**。

> ⚠️ **（若用用户目录那个文件）ACL 是必须的**：Windows 的 `authorized_keys` 若允许 SYSTEM / Administrators / 属主以外的账户写，sshd 会**拒绝该文件**，表现为"公钥明明贴了却还是要密码"。

#### 2.4 手机侧：测试连通

```
ssh <电脑用户名>@<设备名>.<tailnet>.ts.net
```

> 提示：Windows OpenSSH 默认 shell 是 **cmd**；首次连接会问指纹，确认后才走公钥。

**连不上就先查防火墙。** `Add-WindowsCapability` 通常会自动建规则，但它可能被禁用、被组策略改写，
或被安全软件拦掉 —— 症状是**连接超时**，很容易被误判成公钥或 Tailscale 的问题：

```powershell
Get-NetFirewallRule -DisplayName 'OpenSSH*' | Select-Object DisplayName,Enabled,Direction,Action

# 若显示 Disabled 或根本没有：
New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True `
                   -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
```

#### 2.4b 现在才加固：关掉密码登录

**确认 2.4 用公钥能连进来之后**，再编辑 `%ProgramData%\ssh\sshd_config`：

```
PasswordAuthentication no
```

然后 `Restart-Service sshd`。

> ⚠️ **两条纪律**：
> 1. **必须先用公钥成功登录过一次**（也就是上一步真的通了）再来关，否则等于自断退路。
> 2. ⚠️ **别把"留着一个 SSH 窗口"当退路。** `Restart-Service sshd` 会重启服务，而 sshd 的
>    会话进程是它的子进程 —— 现有连接**很可能在重启时一起断掉**（**推测，未实测**；按最坏情况准备总没错）。
>    真正的退路只有两条：
>    - **在电脑本机**留一个窗口待命（物理键鼠，或你 RDP 之外的本地会话）
>    - **先备份配置**，并记下回滚命令：
>      ```powershell
>      Copy-Item "$env:ProgramData\ssh\sshd_config" "$env:ProgramData\ssh\sshd_config.bak" -Force
>      # 回滚：
>      # Copy-Item "$env:ProgramData\ssh\sshd_config.bak" "$env:ProgramData\ssh\sshd_config" -Force
>      # Restart-Service sshd
>      ```


#### 2.5 把这条 SSH 交给手机上的 AI

- **用哪个客户端**：任何能执行 shell / SSH 的手机 AI 客户端都可以（本指南不绑定具体产品）
- **怎么配**：给它一条主机别名 + 私钥路径即可（例如 `Host pc / HostName <域名> / User <用户名> / IdentityFile ~/.ssh/id_ed25519`）
- **允许它做什么**：⚠️ **别写"限定工作目录、只读优先"这种做不到的建议** —— Windows OpenSSH
  **没有**这类原生开关，这条通道实际等于**把整台电脑的 shell 交给手机**。
  真要收窄，只有两条能落地的路径：
  - **专用账户**：新建一个标准用户，只对它放公钥、只授予需要的工作目录，手机用这个账户连
  - **强制命令**：在 `sshd_config` 用 `Match User <该账户>` + `ForceCommand`，把可执行范围钉死到固定脚本

  **在做到上面任一条之前，请把这条 SSH 通道等同于"把整台电脑交给手机"**（另见第 8 节）。

### 步骤 3 · 写「启动脚本」

在**用户目录**（`%USERPROFILE%`，通常是 `C:\Users\你的用户名`）下创建 `dsh-web-start.bat`。

**用记事本创建，保存时编码选「ANSI」**（工作目录含中文时尤其重要）。

```bat
@echo off
REM ===== 按需修改这 3 处 =====
set "DSH_DIR=<dsh.cmd 所在目录>"
REM   上面这项 = 1.3 节 `dir /s /b` 找到的 dsh.cmd 所在目录，【不要再拼任何子路径】
set "WORKDIR=<你的 DSH 工作目录>"
set "TSHOST=<你的设备名>.<你的tailnet>.ts.net"
REM ==========================

if not exist "%WORKDIR%" (
    echo [%DATE% %TIME%] WORKDIR not found: %WORKDIR% >> "%USERPROFILE%\dshweb.log"
    exit /b 1
)
cd /d "%WORKDIR%"
"%DSH_DIR%\dsh.cmd" --profile web --host 127.0.0.1 --port 3081 ^
    --trusted-host "%TSHOST%" --no-open > "%USERPROFILE%\dshweb.log" 2>&1
REM   ↑ 单个 > 是【每次启动覆盖日志】—— 好处是历史 token 不会一直堆在盘上；
REM     想保留历史就改成 >> ，但那样 dshweb.log 会越积越多（v5 起有 2 MB 轮转兜底）。
```

> ⚠️ `DSH_DIR` 要填**1.3 节里 `dir /s /b` 实际找到 `dsh.cmd` 的那个目录**，不一定是上面写的层级。
>
> 💡 两处**加固**（都可直接抄上面的写法）：
> - **`if not exist "%WORKDIR%" ...`**：`cd /d` 失败**不会**中断批处理，dsh 会在一个意外目录里启动，
>   而日志里看不出任何异常。这段检查让它"失败得可见"。
> - **`--trusted-host "%TSHOST%"` 加引号**：设备名若含空格，不加引号会被拆成两个参数。

**参数说明（每个都有用，别删）**：

| 参数 | 作用 |
|---|---|
| `--profile web` | 用 web 配置档 |
| `--host 127.0.0.1` | **只绑本机**（安全设计，不要改） |
| `--port 3081` | 端口。改的话要**同时改 3 处**（见第 6 节故障表「改了端口后连不上」那一行） |
| `--trusted-host <域名>` | **必须**，否则一直"重新连接中"。<br>取值**只写主机名**（可带端口），**不要**带 `https://` 或路径。例如 `mypc.tailxxxx.ts.net` |
| `--no-open` | 不自动开浏览器 |
| `> ...dshweb.log` | 日志（**含访问 token**）。**单个 `>` 是覆盖** —— 每次启动清空，历史 token 不堆积（**安全优先，推荐**）；<br>改成 `>>` 则保留历史，但日志会持续增长（有 2 MB 轮转兜底）。取 token 时**都要取最后一条** |

> 💡 `--trusted-host` 是**可变参**，可以给多个值。
> ⚠️ 但它**只影响 dsh 对 `Host` 头的校验，并不会让服务在局域网上可访问** ——
> 本方案的 `--host 127.0.0.1` 只绑回环，**局域网设备无论如何都连不上**。
> 对外访问**只有 Tailscale 这一条路**。

#### 3.1 先手动测一次

**双击** `dsh-web-start.bat`。

**⚠️ 会弹出黑色窗口，这是正常的。**
**⚠️ 但窗口里不会有任何输出**——所有输出都被重定向进了 `dshweb.log`，所以看起来"什么都没发生"也是正常的。

**验证**（另开一个 CMD）：

```bat
netstat -ano | findstr :3081 | findstr LISTENING
```

**看到一行 `LISTENING` 就成功了。**

**然后停掉**：在那个黑窗口里按 **Ctrl+C**，再关窗口。

> ⚠️ 直接关窗口可能留下残留进程。停下后确认：
> `netstat -ano | findstr :3081` 应**没有输出**。
> 若仍有，用 `taskkill /PID <PID> /F` 清掉。

### 步骤 4 · 写「守护脚本」 ⭐ 核心

在**用户目录**下创建 `dsh-web-guard.ps1`。

> ✅ **这份脚本刻意全部用 ASCII（英文注释）** —— 所以**编码怎么存都不会出错**，不用管 BOM。
>
> **为什么这么设计**：Windows PowerShell 5.1 会把**无 BOM 的 UTF-8** 按 ANSI(GBK) 解析。
> 如果你自己往脚本里加中文注释或中文日志，就**必须**存成「UTF-8 带 BOM」，否则那些字会变成乱码
> （功能通常不坏，但日志就没法看，而第 7 节恰恰要靠看日志判断存活）。
>
> 真要加中文，用这条命令把文件转成带 BOM：
> ```powershell
> $p="$env:USERPROFILE\dsh-web-guard.ps1"
> [IO.File]::WriteAllText($p, (Get-Content $p -Raw), (New-Object Text.UTF8Encoding $true))
> ```

**完整源码（整段复制）**：

```powershell
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
```

> **设计要点 A：为什么"追踪不到会话文件"要报警**
>
> | # | 改动 | 不改会怎样 |
> |---|---|---|
> | 1 | **有人连接却追踪不到任何会话文件时，每 30 秒写一行 `WARN`**（v5 只在启动瞬间写一次） | 这是全文唯一一处「**失败被日志认证为成功**」：追踪不到会话 → 永不重启 → **锁永不释放**，而日志一直显示健康的 `standby` |

> **设计要点 B：为什么"待命"时不计空闲**
>
> | # | 改动 | 不改会怎样 |
> |---|---|---|
> | 1 | **没有追踪到任何会话文件时，空闲计时器关闭**（只写 `standby` 行，永不重启） | v4 会在**无人使用时每约 15 分钟自杀重启一次**：token 每 15 分钟作废、每次 10 秒连接窗口、`dshweb.log` 无限膨胀 —— 而这个进程从未打开过会话，**不可能持有锁**，重启毫无意义 |
> | 2 | `Start-Process` 给 bat 路径**加引号** | 用户名含空格（如 `C:\Users\John Doe`）时，cmd 会去找被截断的路径，bat **从不执行**，而且**完全静默** |
> | 3 | 端口 / 连接正则**锚定到本地地址列** | 原来的 `:3081` 会误匹配远程地址或 `:30810`，有杀错进程的风险 |
> | 4 | 会话目录缺失时**写明确日志**；给 `dshweb.log` 也加 **2 MB 轮转** | `999999` 这个哨兵值把"干净待命"和"目录找不到"混成一个值；`dshweb.log` 无轮转，历史 token 长期明文堆积 |

#### 4.1 手动验证一次

**普通 PowerShell**（不需要管理员）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\dsh-web-guard.ps1"
```

**验证**：

```bat
type "%USERPROFILE%\dsh-web-guard.log"
```

**应看到**：

```
=== guard v6 started (mutex acquired) ===
launched dsh-web-start.bat; waiting for the port...
dsh web is up on port 3081
```

**然后按 Ctrl+C 停掉。**

> ⚠️ Ctrl+C 只停 guard，**dsh web 还在跑**（独立进程），这是正常的——下一步的计划任务会把服务重新拉起来。
>
> ⚠️ **但请先手动清掉这个残留的 dsh web，再进步骤 5**：
> ```bat
> netstat -ano | findstr :3081 | findstr LISTENING
> taskkill /PID <上面那行的 PID> /F
> ```
> **为什么**：guard 判断"启动成功"的唯一依据是**端口 3081 有没有在 LISTENING**，
> 它**不校验监听者是不是自己启动的那个进程**。残留进程还占着端口时，新进程会启动失败，
> 而 guard 照样在日志里写 `dsh web is up on port 3081`，接着监控并最终杀掉那个"**不是它起的**"进程
> —— 功能上往往还能跑，但日志与事实不符，真出问题时你无从判断。

### 步骤 5 · 建计划任务

> 💡 **关于任务名**：下文统一使用 `dsh-web` 和 `dsh-web-keepalive`。**名字可以自定**，
> 但下文**所有** `schtasks` 命令里的任务名都要跟着换。
>
> ⚠️ **`/create` 带 `/f` 会【静默覆盖】同名任务** —— 不报错、不提示。所以建之前先查一次：
> ```bat
> schtasks /query /tn "dsh-web" >nul 2>&1 && echo 已存在！请换个名字，或先确认它是不是本方案建的
> ```
> 若已存在且**不是**本方案建的，请换名，并同步替换下文所有命令。
>
> ⚠️ 反过来：**`/run` `/query` `/delete` 在任务名不存在时才报「系统找不到指定的文件」**。
> 看到这个报错 = **你名字没对上**（不是任务没建成功）。例如本文档写 `dsh-web`，
> 而你实际建的是 `dsh-web-3081`，敲 `schtasks /run /tn "dsh-web"` 就会报它。

> ⚠️ **运行前提（关系到数据安全，别跳过）**
>
> 1. `dsh-web` 必须在该用户的**交互式登录会话**中运行：电脑**开机后必须已有用户登录**，停在登录界面时任务不会启动。
> 2. **不要**把任务改成"不管用户是否登录都运行"，也**不要**在 SSH / RDP 会话里手工起服务。
>    Windows 上会话写锁是**按登录会话划分的具名内核信号量**；两个 dsh 进程不在同一登录会话时，**锁不互斥**，
>    同一个会话日志有被并发写入的风险——这恰恰是 dsh 用锁要防的事。
> 3. 因此建议给这台机器开启**自动登录**，保证"重启 → 自动进入桌面 → guard 起来"，且与桌面版同会话。
> 4. 用 RDP 远程登录会创建**新的登录会话**，可能打断上述前提；用完后建议在物理会话中重新执行
>    `schtasks /run /tn "dsh-web"`。

**必须用管理员 CMD**（不是 PowerShell，原因见下）：

```bat
:: ① 登录时启动 guard
schtasks /create /tn "dsh-web" ^
  /tr "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%USERPROFILE%\dsh-web-guard.ps1\"" ^
  /sc onlogon /f

:: ② 每 5 分钟敲一次门（guard 崩了会被它拉起）
schtasks /create /tn "dsh-web-keepalive" ^
  /tr "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%USERPROFILE%\dsh-web-guard.ps1\"" ^
  /sc minute /mo 5 /f
```

> ⚠️ **必须是 CMD，不能是 PowerShell。** `%USERPROFILE%` 是 CMD 的变量写法；在 PowerShell 里**不会展开**，
> 任务会被写成字面量 `%USERPROFILE%` 然后启动失败。（非要用 PowerShell 就把 `%USERPROFILE%` 换成 `$env:USERPROFILE`。）

**建之前先查同名任务** —— `/f` 会**静默覆盖**同名任务，两个名字都要查：

```bat
for %t in ("dsh-web" "dsh-web-keepalive") do @schtasks /query /tn %t >nul 2>&1 && echo 已存在：%t
```

> 写进 `.bat` 文件时，`%t` 要写成 `%%t`。
> 若查到已存在且**不是**本方案建的，请换名，并同步替换下文所有命令。

> 💡 **可选：消除"每 5 分钟闪一下黑窗口"**
>
> 上面那条 keepalive 用的是 `powershell.exe … -WindowStyle Hidden`。**PowerShell 启动时会先创建控制台窗口再隐藏**，
> 所以桌面或全屏游戏里会**看到每 5 分钟闪一下**（不影响功能，但很烦）。
>
> 彻底消除的办法：改用 `wscript` 以"隐藏窗口"方式启动它。
>
> **1)** 在用户目录建 `dsh-web-keepalive.vbs`（**ANSI / ASCII 编码**）：
> ```vbs
> Set sh = CreateObject("WScript.Shell")
> p = sh.ExpandEnvironmentStrings("%USERPROFILE%")
> sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & p & "\dsh-web-guard.ps1""", 0, False
> ```
>
> **2)** 换掉任务的执行动作（**管理员 PowerShell**）：
> ```powershell
> Set-ScheduledTask -TaskName 'dsh-web-keepalive' -Action (New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('//B "' + "$env:USERPROFILE\dsh-web-keepalive.vbs" + '"'))
> ```
> ⚠️ **不要用 `schtasks /change /tr`** —— 它会**要求输入账户密码**然后卡在那里。
>
> **3)** 触发一次验证：`schtasks /run /tn "dsh-web-keepalive"`
> 成功的判据是**两件事同时成立**：屏幕上**没有**窗口闪现，且 guard 日志里出现新的一行
> `another guard instance is already running; exiting`（说明它确实敲到了门）。
>
> ⚠️ **装了火绒 / 360 之类安全软件的注意**：它们可能把这个 VBS 当成"持久化行为"**直接删掉** ——
> 记得把 `dsh-web-keepalive.vbs` 和 `dsh-web-guard.ps1` 加进**信任区**（见第 6 节）。

**显式确认单实例策略**（"活着就跳过"依赖这个默认值）：

```bat
schtasks /query /tn "dsh-web" /xml | findstr /i MultipleInstances
```

> 期望看到 `IgnoreNew`。若被组策略改成别的值，建议导出 XML 改好后用 `schtasks /create /xml ... /f` 重建。

**立即启动一次**：

```bat
schtasks /run /tn "dsh-web"
```

**验证**（等 30 秒）：

```bat
netstat -ano | findstr :3081 | findstr LISTENING
type "%USERPROFILE%\dsh-web-guard.log"
```

### 步骤 6 · 发布到 tailnet

> **先决条件**：在 Tailscale 管理后台 → **DNS** 页确认已启用 **MagicDNS** 与 **HTTPS Certificates**。
> 未启用时 `tailscale serve` 拿不到证书，手机会访问失败——而这个现象**很容易被误判成"`--trusted-host` 没配对"或"guard 没起来"**。
>
> 可先用这条确认证书能签发（**先切到用户目录，别在 `System32` 里写文件**）：
> ```bat
> cd /d "%USERPROFILE%"
> tailscale cert <你的设备名>.<你的tailnet>.ts.net
> dir <你的设备名>.<你的tailnet>.ts.net.*
> ```
> 它会在**当前目录**生成 `.crt` 和 `.key`（**私钥**）两个文件。验证完删掉：
> ```bat
> del "<你的设备名>.<你的tailnet>.ts.net.crt" "<你的设备名>.<你的tailnet>.ts.net.key"
> ```

**管理员 CMD**（⚠️ **先留档**）—— 注意 `dsh-backup` 目录此刻**还不存在**，所以建目录和留档要一起做：

```bat
mkdir "%USERPROFILE%\dsh-backup" 2>nul
tailscale serve status > "%USERPROFILE%\dsh-backup\serve-before.txt" 2>&1
type "%USERPROFILE%\dsh-backup\serve-before.txt"
```

> ⚠️ **必须先看到 `serve-before.txt` 里有内容，再执行下一条。**
> 若这台机器之前已用 `tailscale serve` 把 443 指向别的服务，下面这条会**顶掉**它；
> 而卸载节的 `--https=443 off` **只会清掉，不会还原** —— 只有留档能救回来。

```bat
tailscale serve --bg 3081
```

> ⚠️ 报 `Access denied` 就用管理员 CMD 重试，或在 Tailscale 设置里把当前用户设为 operator。

**验证**：

```bat
tailscale serve status
```

应看到 `443` 映射到 `http://127.0.0.1:3081`。

### 步骤 7 · 端到端验证

**① 电脑本机**：

```bat
curl -s -o nul -w "%{http_code}" http://127.0.0.1:3081/
```

> ⚠️ 上面这行是给**命令行直接粘贴**的。写进 `.bat` 文件时，`%{http_code}` 要写成 `%%{http_code}`。
>
> ⚠️ **必须在 CMD 里执行。** PowerShell 里 `curl` 是 `Invoke-WebRequest` 的**别名**，参数不兼容会直接报错
> —— 很容易被误判成"服务没起来"。要在 PowerShell 里用，请写成 **`curl.exe`**。

**只要不是 `000`（连接失败）就说明服务在响应**（返回 401/404 都算正常）。

**② 手机浏览器**打开：

```
https://<你的设备名>.<你的tailnet>.ts.net/
```

> **如果要求认证**：
> 1. 在电脑上找**当前有效**的 token（日志是追加的，**必须取最后一条**）：
>    ```bat
>    powershell -NoProfile -Command "Select-String -Path $env:USERPROFILE\dshweb.log -Pattern 'dsh web:' | Select-Object -Last 1"
>    ```
> 2. 从输出里找到形如 `http://127.0.0.1:3081/?token=xxxxxxxx` 的那一行
> 3. 拼到你的地址后面：
>    ```
>    https://<你的设备名>.<你的tailnet>.ts.net/?token=xxxxxxxx
>    ```

> ℹ️ **关于 token，有两件事必须知道**：
> - `?token=` 是**本次进程**的启动令牌。`dsh web` 一重启（guard 空闲重启就会）它**立即作废**，日志里**旧的 token 行同样作废**。
> - 正确的长期姿势是：**首次**用当前 token 打开一次，浏览器会把它换成**有效期 30 天的 cookie**，之后直接访问域名即可。
> - **这个 cookie 能跨 dsh 进程重启存活** —— 依据来自 dsh 源码：签名密钥保存在**持久凭据库**里。
>   `dsh-client-connection/lib/index.js` 的 `BrowserAuth.create()` 用
>   `credentials.modifyRecord(AUTH_RECORD_KEY, …)` 取回已有密钥，**只有首次**才 `randomBytes` 新建；
>   配套注释原文是 *"initialize browser authentication and create its **durable** signing secret"*、
>   *"**persistent** browser-session credential record"*。
>   所以 guard 重启**不会**把你踢下线，**不需要每次去日志里抠 token**。
> - 需要重新取 token 的场景只有：**清了 cookie / 换了浏览器 / 用了无痕模式**。

**③ 验证"用完能释放锁"**（**本方案的关键，务必做**）：

1. 手机上打开一个会话，随便说句话
2. **关闭手机浏览器标签页**（只是切到后台可能仍保持长连接，**必须真正关掉标签**）
3. 等 **最长约 20 分钟**
   > = 文件静默 5 分钟 **+** 空闲 15 分钟。**两段是先后关系，不是取其一。**
   > 想快速验证：临时把 `$FileIdleSec` 改成 `30`、`$TotalIdleSec` 改成 `60`，**验证完务必改回**。
4. 查看日志：
   ```bat
   type "%USERPROFILE%\dsh-web-guard.log"
   ```
   应看到：
   ```
   idle 900s / 900s (conns=0 fileIdle=xxxxs)
   idle threshold reached; restarting to release the session lock (kill PID xxxxx)
   launched dsh-web-start.bat; waiting for the port...
   dsh web is up on port 3081
   ```
5. **确认 PID 变了**：
   ```bat
   netstat -ano | findstr :3081 | findstr LISTENING
   ```
   最后一列的 PID 应和 20 分钟前**不同** → 说明 guard 确实重启过进程。
   > ⚠️ 但**这个推理并不严谨**：新进程照样可能占着锁。**"锁已释放"要以 7⑤ 的双向探针为准**，
   > 这一条只能当作"guard 曾经工作过"的旁证。
6. 在电脑上打开之前"被占用"的会话，**应能正常打开了**

**④ 本次实测记录**（可用来对照你自己机器上的表现是否合理）

| 时刻 | 日志 / 事实 |
|---|---|
| `14:20:21` | `activity detected; idle reset (conns=6 fileIdle=12s)` ← 最后一次活动 |
| `14:23:22` | `heartbeat: alive, conns=0, fileIdle=192s, state=in-use` ← 仍卡在 5 分钟文件静默期内，**不写 idle 行** |
| `14:25:22` | `idle 30s / 900s (conns=0 fileIdle=312s)` ← **首次**进入空闲（312s ≥ 300s） |
| `14:39:53` | `idle 900s / 900s` → `idle threshold reached; restarting to release the session lock (kill PID 8396)` |
| `14:39:58` | `launched dsh-web-start.bat; waiting for the port...` |
| `14:40:03` | `dsh web is up on port 3081` |
| `14:40:33` | `idle 30s / 900s (conns=0 fileIdle=999999s)` ← 哨兵值 = 新进程没打开任何会话 → 不占锁 |

**三点对照说明**：

- **总耗时**：`14:20:21 → 14:39:53` = **19 分 32 秒**，小于 20 分钟上限。
  推演：首次空闲 tick 打出 `30s`，之后每 30 秒 +30，到 900 还需 870 秒 → `14:25:22 + 870s = 14:39:52`，实测 `14:39:53`（差 1 秒）。
- **进入空闲前的日志是"空白"的，属正常**：源码里 `active=true` 且 `totalIdle=0` 时不写日志，所以会看到 1~2 分钟的断档（上表 `14:23:22` 到 `14:25:22` 之间），**不要误判成脚本卡死**。
- **`fileIdle=999999` 是哨兵值，不是异常**：表示"还没记录到任何被追踪的会话文件"（刚重启、还没人连过），说明服务正在干净待命。

**⑤ 7③-6 的客观验证：锁探针**

> 📌 本节说的 **7③-6** 指 7③ 那个编号列表的第 6 小步（"在电脑上打开之前被占用的会话"），
> **不是**第 3 节的「步骤 6 · 发布到 tailnet」，也不是第 6 节（故障排查）。
> 标题里的"不必走到电脑前"只对**已经配好 SSH（步骤 2）**的人成立；
> 人在电脑前的话，直接 `powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\myprobe.ps1"` 就行，
> 不必绕 5.5 的计划任务。

步骤 6 原本要求"你在电脑上点一下"。其实可以**客观地验** —— 因为那把锁是**具名内核信号量**，
名字由**会话目录的完整绝对路径**算出（见第 5.5 节），`OpenExisting` 一下就知道有没有人持有它。

> ⚠️ **两个前提，缺一个就会得到错误结论**：
> 1. **必须在会话 1 里跑**（`Local\` 按登录会话隔离）。SSH 直接跑会得到**永远"空闲"的假阴性**；
>    跨会话执行的写法见第 5.5 节。
> 2. **必须正反各跑一次**。**只跑一次 `NOT FOUND` 什么也证明不了。**

#### 为什么必须"双向对照"

`session.lock` 的路径一旦拼错、或目录名不对（例如只写了会话 ID 的**前 8 位**，
而真实目录名是**完整 UUID**），算出来的信号量名就会**永远不存在** —— 探针会**稳定输出 `FREE`**。
**"名字算错"伪装成"锁已释放"，是这套方法唯一真正的失败模式。**

所以对照要**双向**，两次都符合，结论才成立：

| 时机 | 期望输出 | 它证明了什么 |
|---|---|---|
| **锁确实被持有时**（手机正打开该会话） | `LOCK IS HELD` | **名字算对了**，且探针能识别被持有的对象 |
| **无人使用后** | `LOCK IS FREE` | 锁真的释放了 |

> 📌 早期版本用 guard 的互斥体 `Local\dsh-web-guard` 做对照，但那只证明"**能看见本会话里已存在的内核对象**"，
> **不能**证明信号量名字算对了 —— 所以它**不构成证据**，已移除。

#### 探针脚本

**自动定位会话目录，不用手抄路径**；**纯英文**（原因见步骤 4 的编码说明）。

**怎么用**（三步，别漏）：

1. 在电脑上建 `%USERPROFILE%\myprobe.ps1`，把下面整段粘进去保存（纯 ASCII，有没有 BOM 都无所谓）
2. 用第 5.5 节的办法，以**计划任务**在交互式会话里执行它，输出写到 `%USERPROFILE%\myprobe.txt`
3. ⚠️ **不要直接把它粘贴进 PowerShell 控制台** —— 里面的 `return` 会打断你的会话

```powershell
$out = Join-Path $env:USERPROFILE 'myprobe.txt'   # 结果落盘到这里（计划任务的控制台输出没有去处）
$L   = @()
$L += 'pid=' + $PID
$L += 'sessionId=' + (Get-Process -Id $PID).SessionId   # 应与桌面版 DSH 所在会话号相同（单机典型是 1，用 query session 确认）

$root = Join-Path $env:USERPROFILE '.dsh\sessions'
# 找"最近被写入的会话"所在目录 —— 不要手抄路径，尤其不要只写 UUID 的前 8 位
# dsh 将来改文件名就换这个通配（session*.zstd 不会误匹配 .sessions-trash 里的 *.zstd.trash）
$f = Get-ChildItem $root -Recurse -Filter 'session*.zstd' -ErrorAction SilentlyContinue |
     Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $f) {
    $L += 'no session archive found -- check the sessions layout'
    $L | Out-File -Encoding utf8 $out
    $L
    return
}
$lockPath = Join-Path $f.Directory.FullName 'session.lock'   # 只是名字来源；这个文件并不存在
$sha = [Security.Cryptography.SHA256]::Create()
$hash = ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($lockPath.ToLowerInvariant())) |
         ForEach-Object { $_.ToString('x2') }) -join ''
$name = 'Local\dsh-session-lock-' + $hash
$L += 'sessionDir=' + $f.Directory.FullName
    $L += "lockPath=$lockPath"        # 打印出来，方便核对
$L += "semaphoreName=$name"
try {
    $s = [Threading.Semaphore]::OpenExisting($name)
    $L += 'LOCK IS HELD'
    $s.Dispose()
} catch [Threading.WaitHandleCannotBeOpenedException] {
    $L += 'LOCK IS FREE (semaphore does not exist)'
} catch {
    $L += 'UNKNOWN: 对象可能存在但无法打开(' + $_.Exception.GetType().Name + ') -- 不要当作 FREE'
}
$L | Out-File -Encoding utf8 $out
$L
```

> ⚠️ **`catch` 千万别写成一句 `catch { 'LOCK IS FREE' }`** —— 那会把
> `UnauthorizedAccessException`（对象**存在**但无权限打开，恰恰是**被持有**）也报成"空闲"，结论正好反过来。
> **只有 `WaitHandleCannotBeOpenedException`（对象不存在）才等于 FREE。**

在会话 1 里执行它（计划任务写法见第 5.5 节）。

#### 实测记录（2026-10-04）

> 💡 **下面示例里的 `<你的用户名>` 是作者机器上的 Windows 用户名，请替换成你自己的**。
> ⚠️ **下面的实测输出已脱敏**（路径换成了占位符），所以你**无法**从示例里复算那个哈希 ——
> 不过字段名和形状都是真的，你自己跑一次就能拿到本机的实际值。

**反向（锁被持有时，手机浏览器正开着该会话）**：

```
pid=24292
sessionId=1
sessionDir=C:\Users\<你的用户名>\.dsh\sessions\--<工作目录编码>--\<会话id>
lockPath=C:\Users\<你的用户名>\.dsh\sessions\--<工作目录编码>--\<会话id>\session.lock
semaphoreName=Local\dsh-session-lock-<sha256>

### TARGET: session write-lock semaphore
semaphore => EXISTS  => LOCK IS HELD
```

> 👀 注意 `sessionDir` 那一行：脚本**自动定位**到的会话，正好就是读者刚打开的那一个
> —— 说明"自动定位"和"名字派生"两条都对得上。

**正向（无人使用后）**：

```
sessionId=1
lockPath=C:\Users\<你的用户名>\.dsh\sessions\--<工作目录编码>--\<会话id>\session.lock
semaphore => NOT FOUND  => LOCK IS FREE (nobody holds it)
semaphoreName=Local\dsh-session-lock-<sha256>
```

**结论**：**正反两次都符合**（`HELD` → `FREE`），所以

1. **信号量名字算对了** —— 否则反向那一次不可能命中；
2. **锁确实已经释放** —— 正向那一次对象根本不存在。

步骤 6 的**技术条件成立**：桌面版打开该会话不会再撞上"已被占用"。
（去点 GUI 那一下是"用户可见的最终确认"，不是必需的技术验证。）

---

## 4 · 替换清单

| 占位符 | 换成什么 | 怎么查 | 出现在 |
|---|---|---|---|
| `<dsh.cmd 所在目录>` | **`dsh.cmd` 所在的那个目录**（bat 里的 `DSH_DIR`） | 步骤 1.3 的 `dir /s /b "<安装目录>\dsh.cmd"`，取它**所在的目录**，**不要再拼任何子路径** | 步骤 3 的 `.bat` |
| `<安装目录>` | DSH 桌面版安装根目录，如 `D:\deepseekH`、`%LOCALAPPDATA%\Programs\...` | 桌面快捷方式的属性里能看到 | 步骤 1.3 / 1.4 / 6 |
| `<你的 DSH 工作目录>` | 想让 web 版打开的工作区，如 `D:\DSH工作区` | 你自己定；桌面版里也能看到 | 步骤 3 的 `.bat` |
| `<你的设备名>.<你的tailnet>.ts.net` | 电脑的 Tailscale DNS 名。<br>文中也写作 `<设备名>.<tailnet>.ts.net`、`<tailnet 名>`、`<域名>` —— **都是同一个东西** | Tailscale 后台**整串复制，别手打** | 步骤 2.4 / 3 / 6 / 7② |
| `<电脑用户名>` / `<用户名>` / `<你>` | Windows 登录用户名 | **`whoami`**（比 `%USERNAME%` 可靠，见 2.3 的说明） | 步骤 2.3 / 2.4 / 2.5 |
| `<3081的PID>` / `<上面列出的 PID>` / `<上面那行的 PID>` / `<PID>` | 占用 3081 端口的进程号 | `netstat -ano \| findstr :3081 \| findstr LISTENING`，取**最后一列** | 步骤 3.1 / 7 / 5.5 / 第 6 节 / 第 10 节 |
| `<新端口>` | 你要换成的端口号 | 你自己定 | 第 6 节 |
| `<该账户>` | 走"强制命令"那条路时新建的 SSH 专用账户名（可选） | 你自己定 | 步骤 2.5 |

**`dsh-web-guard.ps1` 无需替换任何内容**——它全部用 `$env:USERPROFILE` 自动定位。

> 💡 7⑤ 的锁探针里**没有任何需要手填的路径** —— 它自己去找最近的会话目录。
> （早期版本要你手抄 `<工作目录编码>` / `<会话id>`，那个做法已经删掉了：手抄的路径一旦错一个字符，
> 算出来的信号量名就永远不存在，探针会**稳定地**报"锁是空闲的"——用一个假结论骗过你。）

---

## 5 · 原理：为什么必须"用完重启"

> **这一节是理解整套方案的关键。** 跳过它，你很可能会觉得 guard 写得太绕，然后改成
> "定时 taskkill + 看门狗"——**那正是实践中踩过的坑**（服务被无脑保活，锁反而被长期占住）。

### 问题

> 手机用完 DSH、关掉浏览器后，**电脑端提示"该会话已被占用"，打不开。**

### 根因（来自 dsh 源码）

会话写锁是**内核级排他锁**：

- **POSIX 上**：`session.lock` 上的非阻塞 `flock(2)`
- **Windows 上**：由同一路径派生的**具名内核信号量**（不落地为文件），**且信号量名按登录会话划分**

源码原话：

> *"A live but wedged holder keeps the lock until its process exits: there is
> deliberately no expiry that could expropriate a stalled writer whose resumed
> appends would tear the log."*
>
> （**逐字**引自 `dsh-session-persistence-jsonl/lib/index.js` 第 624–627 行的注释）

**翻译**：只要进程活着，锁就不放。而且这是**故意设计**的——为了保证会话写入不被两个进程同时破坏。

所以形成死结：

```
关浏览器  ≠  dsh web 进程退出  ≠  锁释放
                                  ↑
                    只有"进程结束"才释放
```

### 解法

| 动作 | 效果 |
|---|---|
| 杀掉进程 | 锁**立刻**被内核回收 |
| 再启动新进程 | 新进程没打开任何会话 → **不占锁**，静静待命 |

### ⏱ 空转节奏：v5 之前它**每 15 分钟自杀一次**

**这是 v4 的真实缺陷，v5 已修** —— 但你必须知道它，否则会误判日志。

v4 的逻辑是这样：重启之后"被追踪的会话文件"是空的 → 文件静默按**哨兵值 `999999` 秒**计算 →
系统立刻被判为空闲 → **空闲计时器马上开始累计** → 900 秒后又杀一次。

于是**无人使用**时的真实节奏是：

```
kill → 约 10 秒窗口期 → 起来 → 空转 15 分 11 秒 → kill → ...
```

**实测证据**（每次重启的时刻；间隔稳定得可怕）：

```
12:11:14 → 12:27:45      13:03:27 → 13:18:38      13:18:38 → 13:33:49
13:33:49 → 13:49:01      14:39:53 → 14:55:04      14:55:04 → 15:10:15
15:10:15 → 15:25:26            ← 全部 ≈ 15 分 11 秒
```

**后果**：token 每 15 分钟作废一次、每 15 分钟有 10 秒连不上、`dshweb.log` 无限膨胀 ——
而这个进程**根本没打开过任何会话，不可能持有锁**，重启纯属白费。

**v5 的修法**：没有追踪到任何会话文件，就意味着**不可能持有锁**，所以**不启动空闲计时器**，只写一行 `standby`：

```
[16:06:23] standby: no tracked session yet; idle timer off (conns=0)
[16:06:53] standby: no tracked session yet; idle timer off (conns=0)
```

**判据**：日志里看到 `standby` 而不是 `idle`，就说明**它正在干净待命、不会自己重启**。

> ⚠️ **但有一种 `standby` 是故障**（v6 起会自己吵出来）：**有人连着**（`conns>0`）却追踪不到任何会话文件。
> 那意味着"锁永远不会被释放"，而日志看起来一切正常。v6 遇到这种情况会写：
> ```
> WARN: conns=2 but no session file tracked under C:\Users\<你>\.dsh\sessions -- lock release will NOT work
> ```
> **看到这行就去查 1.4「检查项 2」** —— 十有八九是 `$SessionsDir` 指的目录不对。

**实测结果（2026-10-04）**：v5 于 `16:05:48` 启动，到 `16:22:24` **已连续 16 分 36 秒**（**超过 15 分钟阈值**）
仍未发生任何重启，3081 的 PID 始终是 `35268`，日志一路是 `standby`。
对照 v4：它在 **15 分 11 秒**时必然重启 —— 所以这条修复**已被实测坐实**。
一旦有客户端连上并被追踪到会话文件，日志会切回 `idle Ns / 900s` —— 那才是"用完释放"的正常过程。

**所以 guard 不是"用完退出"，而是"用完重启"**

```
启动 → 待命 → 你用 → 你走了 → 空闲达阈值 → 重启（释放锁）→ 回到起点
```

**额外好处**：服务一直在待命，下次你打开手机时是**秒开**，没有冷启动等待。

### 为什么空闲判定要两个条件

```
① 端口无 TCP 连接        ← 你没在看
② 会话文件 5 分钟无写入   ← 任务也没在跑
```

**条件 ② 的意义**：任务还在后台跑（但你已关浏览器）时**不会被误杀**。

> ⚠️ **条件 ② 的实现有一个必须知道的细节（v4 已修正）**
>
> 早期版本取的是**整个会话目录里最新的 `.zstd`**，于是：
> - **你在电脑上用桌面版 DSH 时，它会不断刷新文件 mtime** → guard 永远认为"有人在干活" →
>   **永不重启 → 手机端用过的锁一直不释放**（与方案目标相反）
>
> v4 改成：**有手机连接时，记下"此刻被写的那个会话文件"，之后只盯它**。
> 这样**电脑端写别的会话不再干扰判定**。
>
> 代价（已列入第 8 节）：如果你在手机上打开会话 A，之后又在电脑上打开**同一个**会话 A，
> 那么电脑端的写入**仍会**推迟释放——这是符合预期的（同一会话确实有人在用）。

---

## 5.5 · 登录会话与多用户说明

> 把散落在步骤 5 结论、脚本注释里的"会话语义"集中讲清楚。

### 为什么"登录会话"这么重要

Windows 上 dsh 的会话写锁是**具名内核信号量**，名字形如：

```
Local\dsh-session-lock-<hash>
```

`Local\` 前缀意味着：**它只在同一个登录会话内互斥**。

| 场景 | 锁是否互斥 |
|---|---|
| `dsh web` 与桌面版在**同一登录会话**（都在你的桌面里） | ✅ **互斥**（安全） |
| 通过 **SSH / RDP** 起的 `dsh web`，与桌面版**不同会话** | ❌ **不互斥** → 可能并发写同一会话日志 |

**所以**：

- ✅ **正确做法**：让 guard 由计划任务 `onlogon` 启动（自动落在你的交互式会话里）
- ❌ **错误做法**：在 SSH 里 `start` 服务，或把任务设成"不管用户是否登录都运行"

### 顺带：guard 自己的互斥体也是 `Local\`

guard 用 `Local\dsh-web-guard` 保证单实例——**同样只在本登录会话内有效**。
多用户 / 多 RDP 会话场景下，可能出现每个会话各有一个 guard。
**单用户单会话的典型家用场景下，这不是问题。**

### 反过来：怎么**从外部**在"会话 1"里执行命令

有时你**需要**在那台机器的**交互式会话**里跑一条命令（例如 7③ ⑤ 那个锁探针），
但你手上只有 SSH（落在会话 0）。用**计划任务**可以跨过去：

```bat
:: 1) 建一个"仅交互式"任务（/it = InteractiveToken，即跑在已登录用户的活动会话里）
schtasks /create /tn myprobe /tr "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\<你>\myprobe.ps1" /sc once /st 00:00 /f /it

:: 2) 从 SSH 触发它
schtasks /run /tn myprobe

:: 3) 读它写下的输出文件
type %USERPROFILE%\myprobe.txt

:: 4) 用完删掉
schtasks /delete /tn myprobe /f
```

> ⚠️ **`/tr` 的值上限 261 个字符** —— 所以**别把脚本内容塞进 `/tr`**，
> 要写成 `.ps1` 文件再用 `-File` 调用。往电脑上传文件**用 `scp` 最省事**，
> 完全不用跟两层引号搏斗（`scp probe.ps1 pc:/Users/<你>/probe.ps1`）。

**实测（2026-10-04）**：

| 执行方式 | 进程自报的 `sessionId` |
|---|---|
| 直接经 SSH 跑 | `0` |
| 经计划任务 `/it` + `/run` 跑 | **`1`** ✅ |

→ **确认这条路径能把命令送进交互式会话**。这也解释了它能读到桌面会话里的内核对象：
**同会话 = 同一命名空间**。

> 这条技巧是**双向**的：它既是"从外部进会话 1"的办法，
> 也再次证明第 5.5 节的前提——**不这样做，SSH 里的操作永远够不到桌面的锁**。

### 怎么确认当前的会话情况

> ⚠️ **本文档里反复出现的"会话 1"只是本机的示例值**（单用户、没人用 RDP 的典型情况）。
> 多用户 / RDP / 远程登录下会变，**请以实际查询为准**：
> ```bat
> query session
> ```
> 目标：确认 `dsh web`（3081 那个进程）与桌面版**落在同一个会话编号**里。

```bat
:: 看 dsh web 和桌面版是否在同一会话（Session 列应相同）
tasklist /FI "IMAGENAME eq DeepSeek Harness.exe" | findstr /i "DeepSeek"
netstat -ano | findstr :3081 | findstr LISTENING
:: 用上面得到的 PID 查它属于哪个会话
tasklist /FI "PID eq <PID>" 
```

---

## 6 · 故障排查

| 现象 | 原因 | 解决 |
|---|---|---|
| 页面一直**"重新连接中"** | ① 缺 `--trusted-host`<br>② 或取值写错（带了 `https://` / 路径）<br>③ 或 Tailscale 证书没启用 | 确认参数只写**主机名**；确认后台已开 MagicDNS + HTTPS Certificates |
| 报 **`cannot represent developer message`** | 用了旧版 dsh CLI（< `0.2.0-rc.2`）。**本方案 2026-10-03 真实撞到过** | 改用桌面版 runtime 里的 `dsh.cmd`。**确认方法**：对你正在用的那个路径执行 `dsh.cmd --version`，应显示 `0.2.0-rc.2` 或更高；步骤 3 里的 `DSH_DIR` 必须是 `dir /s /b "<安装目录>\dsh.cmd"` 找出来的那个目录 |
| **电脑端会话被占用** | 有进程攥着锁——**先分清是谁**：<br>· 最近在**手机上**用过 → 是 `dsh web`（3081 的进程）<br>· 最近在**电脑桌面版**里打开过 → 是桌面版自己 | 手机端用完 → guard 最长 20 分钟释放；急用 `taskkill /PID <3081的PID> /F`<br>**桌面版持有 → 需在桌面版里关闭该会话/退出桌面版进程，guard 帮不上** |
| 手机能开页面但**一直转圈 / 401** | token 过期（重启后旧 token 作废）或 cookie 被清 | 重新取**最后一条** token（步骤 7②），或直接用新 token 打开一次换 cookie |
| 日志出现 `startup failed` | 端口被占 **或** `DSH_DIR` 路径写错 | 查 `netstat -ano \| findstr :3081`；重新用 `dir /s /b "<安装目录>\dsh.cmd"` 确认真实路径 |
| 服务起来后 **SSH 一断就死** | SSH 会话结束会连带杀进程 | **用计划任务启动**，别在 SSH 里起（同时见 5.5 的会话风险） |
| 日志莫名以 `^C` 结束 | 控制台被中断 | 用计划任务（`-WindowStyle Hidden`）启动，或见下方 VBS |
| **改了脚本但行为没变** | ⚠️ **改磁盘文件不影响运行中的进程** | 必须**重启进程**才生效（见第 7 节） |
| guard 日志**停更** | **先分清 guard 进程到底死没死**（任务管理器看 powershell）：<br>· 进程**不在** → `schtasks /run /tn "dsh-web"` 有效<br>· 进程**还在** → 它卡在退避 sleep 或日志写失败；**此时 `/run` 无效**（互斥体会让新实例直接退出），要按第 7 节「临时停用」那四步**先杀掉 guard** 再 `/run` |
| 日志里每 5 分钟一行 `another guard instance is already running; exiting` | ✅ **正常现象，不是故障** | keepalive 每 5 分钟敲一次门，被单实例互斥体挡住就会写这行。**只要心跳 / `idle` 行还在继续写，就说明主 guard 活着** |
| `--host 0.0.0.0` 报错 | dsh 故意不支持 | 保持 `127.0.0.1`，对外用 Tailscale |
| `schtasks` 建完任务启动失败 | 用了 PowerShell 导致 `%USERPROFILE%` 没展开 | 用 CMD 重建，或改用 `$env:USERPROFILE` |
| `tailscale serve` 报 Access denied | 权限不足 | 管理员 CMD 重试 |
| **服务莫名停掉 / 日志不动，查不到原因** | ⚠️ **很可能被安全软件拦了**（火绒、360、Defender…） | guard 的行为特征（被计划任务唤起 `powershell`、启动 `cmd.exe`、`Stop-Process` 杀掉监听进程）**很容易被 HIPS 当成可疑活动**，而且拦下来是**静默的**。<br>**解决**：把 `%USERPROFILE%` 下这四个文件加进安全软件的**信任区** —— `dsh-web-guard.ps1`、`dsh-web-start.bat`、`dsh-web-keepalive.vbs`、`dsh-web-hidden.vbs`；<br>并翻一下安全软件的**防护日志**，确认有没有拦过 `powershell.exe` / `cmd.exe` |
| **改了端口后连不上** |

### 附：不想看见黑窗口？用这个 VBS

在用户目录建 `dsh-web-hidden.vbs`：

```vbs
Set sh = CreateObject("WScript.Shell")
sh.Run """" & sh.ExpandEnvironmentStrings("%USERPROFILE%") & "\dsh-web-start.bat""", 0, False
```

双击即可**无窗口**启动。

> 正常使用时**不需要它**——guard 本身就用 `-WindowStyle Hidden` 隐藏启动。
> 它只在你想手动启动又不想看黑窗口时用。

---

## 7 · 日常维护

### 判断服务是否健康

| 想知道 | 怎么做 |
|---|---|
| **guard 活着吗** | `type "%USERPROFILE%\dsh-web-guard.log"`，看**最后一行时间戳**，距今 **< 12 分钟** = 正常。<br>⚠️ 为什么不是 10 分钟：心跳周期本身就是 10 分钟，判据取相同值会在临界点随机误报。<br>⚠️ 日志里每 5 分钟会出现一行 `another guard instance is already running; exiting` —— **那是 keepalive 在敲门，正常，不是故障** |
| **dsh web 活着吗** | `netstat -ano \| findstr :3081 \| findstr LISTENING` |
| **当前访问 token** | 见下方——**必须取最后一条** |

**取当前有效 token**（日志是追加的）：

```bat
powershell -NoProfile -Command "Select-String -Path $env:USERPROFILE\dshweb.log -Pattern 'dsh web:' | Select-Object -Last 1"
```

> 💡 **不要用 `-Tail 80`**：万一启动输出很长（插件告警、堆栈），带 token 的那行会被截掉，
> 让你误以为"没有 token"。**直接全文件匹配 `dsh web:`** 更稳。

### 临时停用 / 恢复

```bat
:: 停用（临时不用手机端）—— 【顺序不能变】
schtasks /change /tn "dsh-web" /disable
schtasks /change /tn "dsh-web-keepalive" /disable
rem ① 必须先杀 guard —— 否则它每 30 秒发现端口没了，就把 dsh web 重新拉起来
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*dsh-web-guard*' } | Select-Object -ExpandProperty ProcessId"
taskkill /PID <guard 的 PID> /F
rem ② 再杀 dsh web
netstat -ano | findstr :3081 | findstr LISTENING
taskkill /PID <3081 的 PID> /F
rem ③ 验证：等 60 秒后仍无输出，才算真的停了
netstat -ano | findstr :3081

:: 恢复
schtasks /change /tn "dsh-web" /enable
schtasks /change /tn "dsh-web-keepalive" /enable
schtasks /run /tn "dsh-web"
```

### 参数一览（都在 guard 脚本顶部）

| 参数 | 默认 | 说明 |
|---|---|---|
| `$TotalIdleSec` | 900（15 分钟） | **最常调**。想更快释放锁就改小 |
| `$FileIdleSec` | 300（5 分钟） | 会话文件静默多久算"没在干活"。**不建议低于 300** |
| `$CheckSec` | 30 | 检查间隔 |
| `$HeartbeatSec` | 600（10 分钟） | 心跳频率 |
| `$StartWaitSec` | 180 | 等端口出现的上限；超时即判为启动失败 |
| `$ShortRunSec` | 60 | 运行不足此秒数算失败（防崩溃循环） |
| `$BackoffBase` / `$BackoffMax` | 60 / 1800 | 失败退避：60s → 120s → … 上限 30 分钟 |
| `$LogMaxBytes` | 5MB | 日志超过就轮转一份（`*.log.1`） |
| `$Port` | 3081 | 改的话要**同时改 3 处** |

**⚠️ 改完必须重启 guard**（因为改磁盘不影响运行中的进程）：

```bat
:: 找到并停掉旧 guard
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.CommandLine -like '*dsh-web-guard*' } | Select-Object -ExpandProperty ProcessId"
:: ↑ 若写进 .bat 文件是原样放即可；本命令不含 %，无需转义
taskkill /PID <上面列出的PID> /F

:: 让计划任务拉起新的
schtasks /run /tn "dsh-web"
```

---

### ⑥ 真正的验收：用手机**蜂窝数据**访问一次

前面 ①～⑤ 全是在**电脑跟前、同一个 Wi-Fi 下**做的 —— 它们**排除不了**"机器睡眠""断网""停在登录界面"
这些**真实失效场景**。你在电脑旁测一百遍，也测不出"出门后连不上"。

**唯一算数的验收**：

1. 手机**关掉 Wi-Fi**，改用蜂窝流量
2. 确认手机上的 **Tailscale 是连接状态**
3. 打开 `https://<你的设备名>.<你的tailnet>.ts.net/`

**能正常用 = 这套方案对外面的人来说真的成立了。**

> ✅ **实测通过（2026-10-04）**：关掉手机 Wi-Fi、改用蜂窝流量，**可以正常联通并使用**。
> 这是本项目**第一条"真正在门外"的证据** —— 前面所有验证都是在电脑跟前做的。

> 💡 顺手把另一半也验了：手机停止使用后等约 **20 分钟**，回到电脑上打开那个会话 ——
> **能打开就说明锁也释放了**。

---

## 8 · 安全边界

| 项 | 说明 |
|---|---|
| **只发布到 tailnet** | `tailscale serve` 仅在 tailnet 内可达。**不要**改用 `tailscale funnel`——那才是面向公网的 |
| **tailnet 里的设备都能访问** | **凡是加入你 tailnet 的设备**都能访问该 443 端口，也能尝试连接 22 端口。请确认 tailnet 里没有不该有的设备 |
怀疑泄露时**不要用 `schtasks /run`** —— guard 开头就拿 `Local\dsh-web-guard` 互斥体，
新实例会**直接退出**，`dsh web` 根本不会被重启、**token 也不会变**（那样只会给你错误的安全感）。
正确做法是**杀掉端口上的进程，让正在跑的 guard 自动把它重新拉起来**：
`netstat -ano | findstr :3081 | findstr LISTENING` → `taskkill /PID <最后一列的 PID> /F`，
然后用 `Select-String -Path "$env:USERPROFILE\dshweb.log" -Pattern "dsh web:" | Select-Object -Last 1`
确认那条 token 的**时间戳是刚刚**。<br>⚠️ **cookie 仍然有效**，必要时清掉手机浏览器里该站点的 cookie
| **SSH 加固** | 建议为 SSH 使用专用密钥，并在 `sshd_config` 里设 `PasswordAuthentication no` |
| **`--trusted-host` 的作用域** | 它只是让 dsh 接受该 Host 的 API 请求，**不是**访问控制；真正的边界是 Tailscale |

---

## 9 · 已知限制

| 限制 | 说明 |
|---|---|
| **必须同一登录会话** | 桌面版与 `dsh web` 不在同一 Windows 登录会话时，内核锁**不互斥**，存在并发写同一会话日志的风险（见步骤 5 前提、第 5.5 节） |
| **电脑端活动会推迟释放（同一会话时）** | v4 已把文件静默限定为"手机端用过的那个会话"。但若你在电脑上打开**同一个**会话，它仍会刷新 mtime、推迟释放——这是符合预期的 |
| **强杀可能中断任务** | 若"浏览器已关但任务仍在跑"，而该任务**超过 5 分钟不写会话文件**，理论上可能被误杀。因此 `$FileIdleSec` 不建议低于 300 秒 |
| **token 明文存日志** | `dshweb.log` 里有访问 token（另有 `.log.1` 是轮转保留的上一份）。**本方案默认用 `>` 覆盖模式**，每次重启清空 → 历史 token 不会长期堆积；<br>如果你改成了 `>>`，token 就会一直积累。介意的话把日志重定向到受限目录 |
| **日志会持续增长** | guard 每 30 秒写一行（待命时是 `standby`，追踪到会话后是 `idle`），keepalive 每 5 分钟再写一行。**实测约 1.5 小时 / 237 行 / 15.7 KB**（≈66 字节/行）→ 未轮转时约 138 万行 ≈ **90 MB/年**。<br>v4 起 guard 日志每满 5 MB 轮转（保留一份 `.log.1`）；**v5 起 `dshweb.log` 也每满 2 MB 轮转** → 长期占用的磁盘上限约 **12 MB**，跑多久都不用管 |
| **失败退避未实测** | 脚本里的指数退避 / 短命运行判定逻辑正确，但未在真实故障下验证过 |
| **可能追踪到别的会话文件（v4 残留）** | 记录逻辑是"有人连接时取**全局最新**的 `.zstd`"，**不区分是谁的会话**。若同时满足三条 —— ① 连接瞬间全局最新的是**电脑端**的会话；② 手机这次连接**始终没写自己的会话**（否则 30 秒内自己成为最新，跟踪自动校正）；③ 断开后那个电脑端会话仍**持续被写** —— 则 `fileIdle` 永不增长，**锁不会释放**。任一条不成立即正常释放。在"人在外、电脑无人用"的实际拓扑下几乎不会触发；但 v3 当年正是这样失败的，所以列在这里 |
| **手机端用不了「仅限本机」的管理功能** | 通过域名访问时 `isLoopback=false`，**提供商目录 / 凭据 / 部分设置会被拒**。这是 DSH 的**刻意设计** —— `--trusted-host` 只让 API 请求被接受，**不改变回环判定**。**需要改配置时请在电脑本机操作** |
| **仅 Windows** | 脚本是 PowerShell；Linux/macOS 需要改用 shell + `flock`/`lsof` 重写 |
| **依赖 dsh 内部行为** | 若将来 dsh 改成"自动释放锁"，本方案可弃用（届时 guard 仅剩保活作用） |

---
> 📌 **本方案的定位是「个人自用」** —— 一个 tailnet 里只有你自己的一两台设备。
> 因此「用 Tailscale ACL 把端口限定到某个设备」「给 SSH 建专用账户 + ForceCommand」这类加固**是可选项**；
> 但如果你打算**把访问权限分享给别人**，请先做掉那两件事。


## 10 · 如何停用并清理本方案（含系统改动还原）

> 如果只是**临时不用**，见第 7 节。这一节是**彻底拆掉**。
> ⚠️ 标题里**不再写"完全卸载"** —— 因为本方案会在**系统层面**留下**六处**改动：
> sshd 配置、sshd 服务启动类型、`authorized_keys` 里的公钥、文件 ACL、**电源设置**、**自动登录**。
> **步骤 6 就是用来逐条还原它们的**；跳过步骤 6，你得到的**不是**"干净"。
> ⚠️ 本节所有 `schtasks` 与 `tailscale` 命令均需**管理员 CMD**（或 operator 身份）。

### 先做一次备份（万一以后想恢复）

```bat
set "BK=%USERPROFILE%\dsh-backup\%DATE:~0,4%%DATE:~5,2%%DATE:~8,2%-%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%"
mkdir "%BK%" 2>nul
copy /Y "%USERPROFILE%\dsh-web-start.bat"    "%BK%\"
copy /Y "%USERPROFILE%\dsh-web-guard.ps1"    "%BK%\"
schtasks /query /tn "dsh-web"            /xml > "%BK%\task-dsh-web.xml"
schtasks /query /tn "dsh-web-keepalive"  /xml > "%BK%\task-keepalive.xml"

:: 带时间戳的目录：这样"卸载 → 重装 → 再卸载"不会把上一份好备份盖掉。
:: ⚠️ 任务名不存在时，那两条 /xml 会留下【空文件】。备份完务必看一眼：
dir "%BK%"
:: 应看到 4 个非空文件（2 个脚本 + 2 个 XML）
```

### 步骤 1 · 停掉服务

```bat
:: ① 先禁用任务（否则停掉后 5 分钟内会被 keepalive 拉起来）
schtasks /change /tn "dsh-web" /disable
schtasks /change /tn "dsh-web-keepalive" /disable

:: ② 停掉 guard
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.CommandLine -like '*dsh-web-guard*' } | Select-Object -ExpandProperty ProcessId"
taskkill /PID <上面列出的 PID> /F

:: ③ 停掉 dsh web
netstat -ano | findstr :3081 | findstr LISTENING
taskkill /PID <上面列出的 PID> /F
```

> ⚠️ 上面那条是给**命令行直接粘贴**用的。写进 `.bat` 文件时，里面的 `\"` 要改成 `^"`（CMD 的转义符是 `^`）。

**验证**（应无输出）：`netstat -ano | findstr :3081`

### 步骤 2 · 删除计划任务

```bat
schtasks /delete /tn "dsh-web" /f
schtasks /delete /tn "dsh-web-keepalive" /f
```

**验证**：`schtasks /query /tn "dsh-web"` 应提示找不到。

### 步骤 3 · 撤销对外发布

```bat
tailscale serve --https=443 off
```

**验证**：`tailscale serve status` 应显示无 443 映射。

> ⚠️ **只撤 serve，不要卸载 Tailscale**——除非你确定以后不再需要。

### 步骤 4 · 删除文件

```bat
del "%USERPROFILE%\dsh-web-start.bat"
del "%USERPROFILE%\dsh-web-guard.ps1"
del "%USERPROFILE%\dsh-web-guard.log"
del "%USERPROFILE%\dsh-web-guard.log.1"
del "%USERPROFILE%\dshweb.log"
del "%USERPROFILE%\dshweb.log.1" 2>nul
del "%USERPROFILE%\myprobe.ps1"  2>nul
del "%USERPROFILE%\myprobe.txt"  2>nul

> 💡 **`dsh-backup\` 和里面的 `serve-before.txt` 是【有意保留】的** —— 那是留档，用来回滚和还原你原来的 443 映射，不要删。
del "%USERPROFILE%\dsh-web-hidden.vbs"
del "%USERPROFILE%\dsh-web-keepalive.vbs"
```

### 步骤 5 · （可选）关闭 SSH 服务

> ⚠️ **先问自己一句话：这台机器上的 OpenSSH，是你本来就装的，还是本方案让你装的？**
>
> - **本来就是你的**（你以前就用 SSH 管这台机器）→ **跳过整步**。
>   下面的 `Set-Service ... Disabled` 和 `Remove-WindowsCapability` 会**打断你原有的远程管理通道**，
>   而且一旦执行，**只能走到电脑前**才能修回来。
> - **是为本方案装的** → 可以执行。

```powershell
Stop-Service sshd
Set-Service -Name sshd -StartupType Disabled
```

彻底移除 OpenSSH 服务端（一般不需要）：

```powershell
Remove-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
```

### 步骤 6 · ⚠️ 还原系统层面的改动（**别跳过**）

前 5 步拆掉的是"本方案自己加的东西"。下面这几处是**改到系统上的**，不还原就等于**没卸干净**。

**6a. 删掉 `authorized_keys` 里那把手机公钥**

> ⚠️ **如果你按 2.3 走的是 ProgramData 那条路，这把公钥在 `%ProgramData%\ssh\administrators_authorized_keys` 里，不在用户目录！**
> 两个都查一下，删掉 `dsh-phone` 结尾的那一行：
> ```bat
> notepad "%USERPROFILE%\.ssh\authorized_keys"
> notepad "%ProgramData%\ssh\administrators_authorized_keys"
> ```

```bat
mkdir "%USERPROFILE%\dsh-backup" 2>nul
copy /Y "%USERPROFILE%\.ssh\authorized_keys" "%USERPROFILE%\dsh-backup\authorized_keys.bak"
::   （若你刚做过上面的"先做一次备份"，也可以改存到 %BK%\ 里，跟其他备份放一起）
:: 用记事本打开，删掉以 dsh-phone（或你生成密钥时写的注释）结尾的那一行，保存
notepad "%USERPROFILE%\.ssh\authorized_keys"
```

> ⚠️ **这一步不做，手机私钥就仍然能登录这台电脑** —— 那"完全卸载"就是一句假话。
> ⚠️ **但反过来也要知道**：删掉它，`ssh pc "命令"` 就**彻底失效**了（手机再也登不进来）。
> 如果你还想让手机继续操作电脑，就**保留这一行，只做 6b / 6c / 6d**。

**6b. 恢复密码登录**（如果你当初按 2.4b 关掉了，而你现在还需要它）

```powershell
Copy-Item "$env:ProgramData\ssh\sshd_config" "$env:ProgramData\ssh\sshd_config.bak-uninstall" -Force
(Get-Content "$env:ProgramData\ssh\sshd_config") -replace '^\s*PasswordAuthentication\s+no', 'PasswordAuthentication yes' |
    Set-Content "$env:ProgramData\ssh\sshd_config"
Restart-Service sshd
```

**6c. 恢复 `authorized_keys` 的权限继承**（2.3 的 `icacls /inheritance:r` 把它永久改掉了）

> ⚠️ **两个落点都要处理** —— 2.3 已经告诉过你：管理员账户下 sshd 读的是
> `%ProgramData%\ssh\administrators_authorized_keys`，而**那个文件也被执行过 `icacls /inheritance:r`**。
> 先确认你当初实际用的是哪个（回到 2.3 的那条 `findstr`），再对**同一个**执行：
> ```bat
> icacls "%USERPROFILE%\.ssh\authorized_keys" /inheritance:e
> :: 若你用的是 ProgramData 那条路：
> icacls "%ProgramData%\ssh\administrators_authorized_keys" /inheritance:e
> ```

```bat
icacls "%USERPROFILE%\.ssh\authorized_keys" /inheritance:e
```

> `/inheritance:e` 会**重新启用继承**，回到改动前的状态。想留档就先跑一次 `icacls "%USERPROFILE%\.ssh\authorized_keys"`。

**6d. Tailscale 的 443 映射**

步骤 3 的 `tailscale serve --https=443 off` **只会清掉映射，不会还原你原来的配置**。
如果本方案之前你就把 443 指向了别的服务，请按当时存下的 `serve-before.txt` 重新配置：

```bat
type "%USERPROFILE%\dsh-backup\serve-before.txt"
:: 然后按里面的内容重新跑对应的 tailscale serve 命令
```

**6e. 还原电源设置**（1.4「检查项 1」改过的）

```bat
:: 把数值改回你原来的（下面是常见默认值，请按你机器实际情况调整）
powercfg /change standby-timeout-ac 30
powercfg /change hibernate-timeout-ac 180
powercfg /change monitor-timeout-ac 15
powercfg /change standby-timeout-dc 15
powercfg /change hibernate-timeout-dc 60
powercfg /change monitor-timeout-dc 5
```

> ⚠️ **不要用 `powercfg /restoredefaultschemes`** —— 那会清掉你这台机器上**所有**自定义电源设置。

**6f. 关闭自动登录**（1.4「检查项 3」开过的）

```bat
:: 用 netplwiz 开的，就再用 netplwiz 把勾打回去
netplwiz
```

或者用命令清掉 Winlogon 里的凭据（管理员 CMD）：

```bat
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /f
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /f
```

> ⚠️ **这一步不做，这台机器会一直"开机免密进桌面"** —— 而你还以为已经卸干净了。

**6g. 清理安全软件的信任区**（如果你当初按第 6 节加过）

卸载后那四个文件都没了，但信任区里的条目还留着 —— 顺手删掉，别留一堆指向不存在文件的例外。

### ✅ 重要：卸载**不影响**你的 DSH 数据

| 保留的东西 | 说明 |
|---|---|
| `%USERPROFILE%\.dsh\` | **你的所有会话记录都在这里** |
| DSH 桌面版本体及配置 | 完全不动 |
| Tailscale 本身 | 只是撤掉了 serve 映射 |

**所以卸载是安全的**——随时可以按第 3 节重新部署，**会话一条都不会丢**。

### 回滚（从备份恢复）

```bat
:: ⚠️ 备份在【带时间戳的子目录】里，先把 BK 指向你那一份：
set "BK=%USERPROFILE%\dsh-backup\20261004-140903"
::    ↑ 改成你实际的目录名。看有哪些：
::      dir /b /ad /o-d "%USERPROFILE%\dsh-backup"

copy /Y "%BK%\dsh-web-start.bat" "%USERPROFILE%\"
copy /Y "%BK%\dsh-web-guard.ps1" "%USERPROFILE%\"
schtasks /create /tn "dsh-web"           /xml "%BK%\task-dsh-web.xml" /f
schtasks /create /tn "dsh-web-keepalive" /xml "%BK%\task-keepalive.xml" /f
schtasks /run /tn "dsh-web"
tailscale serve --bg 3081
```

> 早期版本这里写的是 `%USERPROFILE%\dsh-backup\` 直接复制 —— 而备份实际落在**带时间戳的子目录**里，
> 那样恢复必然报"找不到文件"。

---

## 附录 · 一页速查

```
【文件】都在 %USERPROFILE% 下：
   dsh-web-start.bat     启动 dsh web
   dsh-web-guard.ps1     守护脚本（核心）
   dsh-web-guard.log     守护日志（判断存活看这里；超 5MB 自动轮转为 .log.1）
   dshweb.log            dsh 日志（含 token，取【最后一条】）
   dsh-web-hidden.vbs    （可选）无窗口手动启动

【任务】两个：
   dsh-web            登录时启动 guard
   dsh-web-keepalive  每 5 分钟保活

【发布】
   tailscale serve --bg 3081

【访问】
   https://<设备>.<tailnet>.ts.net/

【关键数字】
   空闲释放最长 ≈ 20 分钟（文件静默 5 分钟 + 空闲 15 分钟，先后关系）
   当前 token = dshweb.log 里最后一条 token=

【排查三板斧】
   netstat -ano | findstr :3081 | findstr LISTENING
   type "%USERPROFILE%\dsh-web-guard.log"
   schtasks /run /tn "dsh-web"

【临时停用 / 恢复】   见第 7 节
【彻底卸载 / 回滚】   见第 10 节（不会动你的 .dsh 会话数据）
```
