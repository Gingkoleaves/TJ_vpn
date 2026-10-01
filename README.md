# 同济校园 VPN：Windows 原生 OpenConnect + Clash

用 OpenConnect 的 Array 协议替代卡死的 MotionPro，让 Windows 直接建立校园 VPN。Clash 保持开启，外网沿用原代理，指定校园目标通过独立 Wintun 网卡连接。

**状态：0.3.0 GUI 预发布。用户已确认原生脚本连接成功；GUI 密码输入、后台认证管道和四按钮界面已经实现。真实校园密码的后台登录、持续连接及第二台电脑仍待验证。** 当前仍为预发布。

## 快速开始

使用 `dist/tongji-openconnect-0.3.0-preview.2-windows-x64.zip`，可不安装 Rust。安装好 7-Zip 后解压整个 ZIP，双击 **TongjiVPN.exe**。面板使用普通权限，连接时请求管理员权限，后台 shell 不显示。再次运行会唤起已有窗口。`StartGUI.cmd` 是备用入口；不要把 exe 单独移走，也不要在 ZIP 内直接运行。

1. **配置**：填写校内主机 IP，每行一个；只展示 IP，不展示 VPN、DNS 或 Clash 参数。
2. 在主界面输入校园账号和密码，点击 **连接**，允许 UAC。首次连接会自动准备客户端，authgroup 自动填空，不需要管理员终端输入。
3. **日志**：查看下方连接进度及错误。校园网卡已连接表示配置就绪；可以用 SSH 或下述命令检查实际可达性。
4. **断开**：请求后台程序退出，清理校园路由并恢复 Clash。已建立连接后关闭面板，连接继续运行。

主界面只保留 **连接、断开、配置、日志** 四个按钮。密码框使用掩码；凭据通过限制当前 Windows 用户访问的随机命名管道交给后台进程，双方核对进程 ID。密码仅驻留进程内存，不写入配置、文件或命令行参数；管道传递后清空密码框。标准输出先脱敏，再进入面板日志。

本版没有保存密码或开机免密服务。纯命令行使用者仍可双击 **Start.cmd**，在本机终端输入账号密码。

也可以手动准备客户端：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1
```

Setup 从官方项目下载固定版本 OpenConnect，校验 SHA256 后解包；需要已安装 7-Zip。没有把 VPN 安装器、驱动安装向导或 WSL 作为启动流程。Wintun 由客户端创建接口时加载，需要管理员权限。

**Start.cmd** 请求管理员权限，在本机终端启动 VPN：

- `authgroup`：**留空，直接回车**。
- `username`：同济统一身份认证账号。
- `password`：在本机输入，不写入文件、不传给助手、不作为命令行参数。

保持窗口运行；自动配置就绪后出现 `READY`。初次出现 READY 只代表路由/Clash 配置已应用，需要执行连接测试确认目标实际可达。Ctrl+C 断开后程序尝试清理自己的路由并恢复 Clash。

命令行方式，在管理员 PowerShell 中运行：

```powershell
.\Connect.ps1
```

源码使用者先 `Setup.ps1`、`Build.ps1`。Build 需要 Rust stable 和 Windows C++ 链接工具；便携包包含已构建的 helper，不需要 Rust/Python/Node。

## 验证

```powershell
.\Doctor.ps1
.\Status.ps1
.\Test-Connection.ps1
ssh user@192.0.2.10
```

测试同时访问校园软件站和 Google，经现有 Clash 的混合代理端口。SSH 密码仅在本机输入。长时间采样：

```powershell
.\Test-Connection.ps1 -Count 60 -IntervalSeconds 10
```

结果保存在忽略跟踪的 `runtime/checks.csv`。窗口关闭或 VPN 退出后校园测试应失败，外网代理应继续工作。

## 配置校园目标

Setup 创建 `config.local.json`；它不会被 Git 跟踪。默认校园目标为：

- `192.0.2.10/32`：SSH 服务器。
- `software.tongji.edu.cn`：由校园 DNS 查询真实 IPv4，再添加精确 /32 路由。
- 校园 DNS：取自登录后学校实际下发的服务器。

GUI 配置只接受明确的 IPv4 主机地址，自动去重并生成 /32 路由；拒绝默认地址、fake-IP、回环、组播、域名及 CIDR 网段。修改后重连生效。源码高级用户仍可直接修改 `config.local.json`；GUI 保存会把 `routes` 替换为主机列表，其他内部配置保持原样。

**当前提供指定目标的分流，并非学校全网自动发现。** `domainSuffixes` 决定 Clash 的校园规则和 DNS 策略，但域名对应的目标仍需列入 `hosts` 或由 `routes` 覆盖。第三方图书馆数据库、IPv6、其他学校、多因素/浏览器认证没有验证。

服务器、网卡名、Clash 端口和命名管道都可配置。默认 Clash Verge Rev 路径按当前用户 APPDATA 自动定位；自定义路径可用：

```powershell
.\Connect.ps1 -ClashDirectory 'C:\your\clash-config' -MihomoPath 'C:\your\verge-mihomo.exe'
```

必须使用规则模式和 TUN；程序不会切换你的模式或停用 Clash。没有 Clash 时可用 `Connect.ps1 -NoClash` 建立指定目标的原生路由，但该模式未验证。

## 连接架构

```text
OpenConnect Windows ── Array SSL VPN ── 同济网关
          │
          └─ Wintun「TongjiVPN」：指定校园 IP 与 DNS 的专用路由

Windows SSH ── 校园目标专用路由 ── TongjiVPN ── 校内服务器
校园网页 ── Clash 校园规则 ── 绑定 TongjiVPN 的 DIRECT 出口
其他网页 ── 原 Clash 规则与原外网节点
```

学校下发的 `0.0.0.0/0` 被忽略，不更改系统全局 DNS，不增加校园默认路由。原 Clash TUN、端口、订阅节点和手选代理组保持不变。原生方案不需要 Ubuntu 和 SOCKS 中转。

## 恢复与可靠性设计

每次连接的网卡名带随机后缀（例如 `TongjiVPN_a1b2c3d4`），实际名称以 Status 输出为准；`interfaceName` 配置现在用作名称前缀。这用于绕过 OpenConnect 对残留同名 Wintun 记录的打开失败，不重置其他网络适配器。会话配置仅写入忽略跟踪的 `runtime/session-config.json`。

- 独占锁防止启动多个本仓库连接；OpenConnect 内置重连，默认超时由上游决定。
- 原子写入状态文件；只记录接口/路由，不记录密码、cookie、完整环境变量或 HTTP 认证流量。
- Windows hook 有 10 秒上游时限；DNS 和 Clash 工作移到父进程执行。
- 添加路由前验证接口名称、Wintun 描述及目标；恢复时再次核对，避免接口编号复用后删除其他 VPN 的路由。
- 配置生成由 Rust 解析 YAML；先由 Mihomo 校验，再通过本机命名管道加载，失败尝试回滚。
- 原全局增强脚本与运行配置先备份，手选代理组在加载后恢复。检测到用户后来修改全局脚本，会拒绝自动覆盖。
- 没有保存密码，因此没有无人值守 Windows 服务/开机免密登录。GUI 输入后由后台进程认证，关闭管理窗口不会结束已建立的校园连接。

遇到终端被强制关闭或清理失败，在管理员 PowerShell 执行：

```powershell
.\Recover.ps1
```

它仅停止本仓库记录且路径/启动时间匹配的 OpenConnect，清理记录的校园路由，再恢复备份的 Clash 配置。若全局增强脚本被你另行修改，会保留修改并提示手动合并。

不要关闭 Clash：Codex 的外网连接依赖它。恢复脚本也不退出 Clash。

## 开发与交付

```powershell
.\Test.ps1
.\Build.ps1
.\Package.ps1
git log --oneline
```

PowerShell / WinForms 负责管理面板、生命周期与 Windows 网络接口，Rust 负责 exe 启动器及 YAML/增强脚本生成。Rust lockfile 已提交；GitHub Actions 在 Windows 跑本地测试，不进行校园登录。ZIP 使用明确的文件白名单，不包含运行状态、账号配置、用户订阅、代理凭据或周围工作目录；附带 SHA256 文件。

具体验证结果见 [docs/VALIDATION.md](docs/VALIDATION.md)。

## 官方参考

- [OpenConnect Array 协议](https://www.infradead.org/openconnect/array.html)
- [官方 Windows 构建说明](https://www.infradead.org/openconnect/packages.html)
- [Mihomo 出口绑定接口](https://wiki.metacubex.one/config/proxies/direct/)
- [Mihomo DNS 绑定代理/接口](https://wiki.metacubex.one/config/dns/)

本项目非同济大学、Array Networks 或 OpenConnect 官方产品。
