# 同济校园 VPN：Windows 原生 OpenConnect + Clash

用 OpenConnect 的 Array 协议替代卡死的 MotionPro，让 Windows 直接建立校园 VPN。Clash 保持开启，外网沿用原代理，指定校园目标通过独立 Wintun 网卡连接。

**状态：0.3.0 GUI 预发布。用户已确认 Windows 原生连接与校园 SSH 登录成功；长时间运行、网络切换及第二台电脑仍待验证。**

## 快速开始

使用 `dist/tongji-openconnect-0.3.0-preview.7-windows-x64.zip`，可不安装 Rust。安装好 7-Zip 后解压整个 ZIP，双击 **TongjiVPN.exe**。面板使用普通权限，连接时请求管理员权限，后台 shell 不显示。再次运行会唤起已有窗口。`StartGUI.cmd` 是备用入口；不要把 exe 单独移走，也不要在 ZIP 内直接运行。

1. **配置**：填写校内主机 IP 或域名，每行一个；不展示 VPN、DNS 或 Clash 参数。例如：

   ```text
   192.0.2.10
   node.campus.example
   ```
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
ssh <校内主机账号>@<校内主机IP>
```

测试同时访问校园软件站和 Google，经现有 Clash 的混合代理端口。SSH 密码仅在本机输入。长时间采样：

```powershell
.\Test-Connection.ps1 -Count 60 -IntervalSeconds 10
```

结果保存在忽略跟踪的 `runtime/checks.csv`。窗口关闭或 VPN 退出后校园测试应失败，外网代理应继续工作。

## 配置校园目标

Setup 创建本地 `config.local.json`，初始目标为空。通过配置按钮添加自己的 IP 或域名；账号、目标、日志和运行状态均不纳入 Git 或发布包。文档中的 `192.0.2.10` 和 `node.campus.example` 是示例，请替换为实际目标。

GUI 配置接受 IPv4 主机地址或完整域名，自动去重、规范域名大小写；不接受 URL、端口、通配符或 CIDR 网段。修改后重连生效。保存为统一 `targets` 列表，同时生成内部 `routes` / `hosts`；兼容没有 `targets` 的旧配置。若存在 `targets`，它是目标列表的唯一来源。

源码高级用户也可修改 JSON：

```json
"targets": ["192.0.2.10", "node.campus.example"]
```

连接时先绑定校园网卡查询学校 DNS（TCP，必要时回退 UDP）；失败时通过现有 Clash 外网代理查询 Google 公网 DoH。取得的 IPv4 加入校园专用路由，并缓存为 Clash 的精确域名映射，后续访问仍通过校园隧道。无需修改 Windows hosts 文件或全局 DNS。域名仅在连接/重连时解析；若学校改变 IP，需要重连刷新。

如果校园和公网解析都失败，面板显示“部分域名未解析”并记录 DNS 具体错误，VPN 和其他 IP 目标继续工作。NXDOMAIN 表示对应解析器找不到该域名，不能通过更换访问路由解决；仅校内存在的域名仍依赖可用的校园 DNS。公网回退只适用于实际有公网 DNS 记录的名称。

校内专有域名可能不出现在公网 DNS 中。可在本地创建 `config.hosts.local.json`，维护文档确认的备用 IPv4 地址；该文件被 Git 忽略，也不会打包。实时校园 DNS 优先，其次公网 DoH，最后本地备用表。备用地址可能过期，使用时日志会提示。示例结构（请换成自己的主机）：

```json
{"hosts":{"node.campus.example":["192.0.2.10","192.0.2.11"]}}
```

对于本地备用表中的超算主机，路由建立后探测 10022 端口的 SSH 握手，优先把能响应的地址交给 Clash；全部超时时保留原地址供重试。探测只读取 SSH 握手，不提交账号密码。

```powershell
.\Test-Hpc.ps1
ssh -p 10022 <超算平台账号>@<校内域名>
```

`Test-Hpc.ps1` 检查当前已配置域名的 10022 端口，结果仅保存在 `runtime/hpc-checks.csv`。超算平台账号可能与校园 VPN 账号不同，端口以学校说明为准。

**当前提供指定目标的分流，并非学校全网自动发现。** 在配置中添加域名，会自动进入校园域名规则和 DNS 策略，不需要手动编辑后缀。网页若重定向到其他校内域名，应把跳转目标也加入列表。第三方图书馆数据库、IPv6、其他学校、多因素/浏览器认证没有验证。

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
