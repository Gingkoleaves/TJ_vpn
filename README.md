# 同济校园 VPN：Windows 原生 OpenConnect + Clash

用 OpenConnect 的 Array 协议替代卡死的 MotionPro，让 Windows 直接建立校园 VPN。Clash 保持开启，外网沿用原代理，指定校园目标通过独立 Wintun 网卡连接。

**状态：0.1.0 预发布。Windows x64 原生客户端与生成配置已验证；Windows 实际登录、真实路由配置、持续连接和断开恢复仍待本机验证。不要把预发布当作已验证的生产级服务。** WSL OpenConnect 登录同济及 SSH 校内服务器已在此前实测成功，但不作为 Windows 原生版本的成功证据。

## 快速开始

使用 `dist/` 中的便携 ZIP，可不安装 Rust。解压到普通目录，先运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1
```

Setup 从官方项目下载固定版本 OpenConnect，校验 SHA256 后解包；需要已安装 7-Zip。没有把 VPN 安装器、驱动安装向导或 WSL 作为启动流程。Wintun 由客户端创建接口时加载，需要管理员权限。

然后双击 **Start.cmd**。它请求管理员权限，在本机终端启动 VPN：

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

添加 IP 或网段到 `routes`，添加资源域名到 `hosts`，重连生效。允许 /8 到 /32 的规范 IPv4 网段，拒绝默认路由、fake-IP、回环及组播目标。仅添加你确实需要的校园范围，避免与本地网络重叠。

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

- 独占锁防止启动多个本仓库连接；OpenConnect 内置重连，默认超时由上游决定。
- 原子写入状态文件；只记录接口/路由，不记录密码、cookie、完整环境变量或 HTTP 认证流量。
- Windows hook 有 10 秒上游时限；DNS 和 Clash 工作移到父进程执行。
- 添加路由前验证接口名称、Wintun 描述及目标；恢复时再次核对，避免接口编号复用后删除其他 VPN 的路由。
- 配置生成由 Rust 解析 YAML；先由 Mihomo 校验，再通过本机命名管道加载，失败尝试回滚。
- 原全局增强脚本与运行配置先备份，手选代理组在加载后恢复。检测到用户后来修改全局脚本，会拒绝自动覆盖。
- 没有保存密码，因此没有无人值守 Windows 服务/开机免密登录。当前产品形态为前台连接程序，认证必须由用户完成。

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

PowerShell 负责生命周期与 Windows 网络接口，Rust 负责 YAML/增强脚本生成。Rust lockfile 已提交；GitHub Actions 在 Windows 跑本地测试，不进行校园登录。ZIP 使用明确的文件白名单，不包含运行状态、账号配置、用户订阅、代理凭据或周围工作目录。

具体验证结果见 [docs/VALIDATION.md](docs/VALIDATION.md)。

## 官方参考

- [OpenConnect Array 协议](https://www.infradead.org/openconnect/array.html)
- [官方 Windows 构建说明](https://www.infradead.org/openconnect/packages.html)
- [Mihomo 出口绑定接口](https://wiki.metacubex.one/config/proxies/direct/)
- [Mihomo DNS 绑定代理/接口](https://wiki.metacubex.one/config/dns/)

本项目非同济大学、Array Networks 或 OpenConnect 官方产品。
