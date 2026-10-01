# 同济校园 VPN（Windows）

使用 OpenConnect 的 Array 协议连接同济校园 VPN，并通过独立 Wintun 网卡为指定校园 IP 和域名建立路由。提供中文 GUI，支持没有代理时直连，以及与正在运行的 Clash Verge Rev 联动。

**当前版本：0.3.0-preview.8（预发布）。** 用户已确认 Clash 开启和关闭时均可成功登录；长时间运行、网络切换和第二台电脑仍待验证。详细记录见 [验证记录](docs/VALIDATION.md)。

## 下载与运行

普通用户请从 **[GitHub Releases](https://github.com/Gingkoleaves/TJ_vpn/releases)** 下载发布附件，无需安装 Rust、Python 或 Node.js。

当前版本的文件：

- [Windows x64 便携包（ZIP）](https://github.com/Gingkoleaves/TJ_vpn/releases/download/v0.3.0-preview.8/tongji-openconnect-0.3.0-preview.8-windows-x64.zip)
- [SHA256 校验文件](https://github.com/Gingkoleaves/TJ_vpn/releases/download/v0.3.0-preview.8/tongji-openconnect-0.3.0-preview.8-windows-x64.zip.sha256)
- [版本说明](https://github.com/Gingkoleaves/TJ_vpn/releases/tag/v0.3.0-preview.8)

仓库保存源代码，**不包含 `dist/` 和已编译的 `TongjiVPN.exe`**。GitHub 自动提供的 **Source code (zip/tar.gz)** 是源码，不是可直接运行的便携包。`dist/` 仅在本地执行打包脚本后生成。

### 使用要求

- Windows x64；目前主要在 Windows 11 上验证。
- 有效的同济校园 VPN 账号和密码。
- 已安装 7-Zip，供首次准备 OpenConnect 时解包使用。
- 首次运行能够下载 OpenConnect；连接和恢复操作需要允许 Windows UAC 管理员权限。
- 如使用代理联动，需运行 Clash Verge Rev，并启用规则模式和 TUN。

### 快速开始

1. 下载上面的便携包，将**整个 ZIP** 解压到可写目录。
2. 双击解压目录中的 **TongjiVPN.exe**；`StartGUI.cmd` 是备用入口。不要单独移动 exe，也不要直接在 ZIP 中运行。
3. 点击 **配置**，填写实际校园主机 IP 或完整域名，每行一个。发布包的目标列表默认为空。例如：

   ```text
   192.0.2.10
   node.campus.example
   ```

   以上地址仅作格式示例，需要替换为自己的校园目标。
4. 连接方式保持 **自动选择（推荐）**，在窗口内输入校园账号和密码，点击 **连接** 并允许 UAC。首次连接会自动下载、校验并解包 OpenConnect。
5. 等待日志显示配置完成，再点击 **连接测试**，或使用 SSH、浏览器访问已配置的校园目标。网卡已连接不等于每个目标都已实际可达。
6. 使用结束后点击 **断开**，清理校园路由和本次域名映射；代理联动模式会恢复此前的 Clash 配置。

**关闭管理窗口不会断开已建立的 VPN。** 需要退出校园连接时，请重新打开窗口并点击“断开”；清理失败时使用“异常恢复”。

## 连接方式与 GUI

| 连接方式 | 适用环境 | 行为 |
| --- | --- | --- |
| 自动选择（推荐） | 不确定是否有运行中的代理 | 有代理时检测联动条件；没有代理时使用校园直连 |
| 校园 VPN 直连 | 没有运行中的代理 | 使用原生校园路由，不依赖 mihomo |
| 校园 VPN + 代理联动 | Clash Verge Rev 正在运行 | 校园目标使用校园隧道，外网沿用现有代理 |

检测到运行中的代理但联动条件不满足时，程序会显示错误，不自动降级为直连，也不会关闭代理。显式直连模式同样会拒绝检测到运行中代理的环境，以避免 TUN 拦截校园流量。

主界面操作：

- **连接 / 断开**：建立或结束校园连接。
- **配置**：编辑校园 IP 和域名；保存后重连生效。
- **日志**：查看进度、解析结果和错误。
- **重新检测 / 代理设置**：检查代理环境，选择 mihomo 内核文件、Clash Verge 配置目录，并设置控制管道和代理端口。
- **连接测试**：在窗口内显示校园软件站和外网测试结果。
- **异常恢复**：请求管理员后台清理本项目记录的连接，并在窗口内显示结果。

内核按用户指定路径、运行进程、Clash Verge 程序目录、PATH 和常见安装位置查找。独立 mihomo 可以被发现，但**配置联动目前要求 Clash Verge 的配置文件结构**，不代表兼容所有 mihomo 客户端。

## 校园目标与域名解析

GUI 接受 IPv4 主机地址或完整域名，会去重并规范域名大小写；不接受 URL、端口、通配符或 CIDR 网段。本项目只为配置中的目标分流，不自动发现整个校园网。网页若跳转到另一个校内域名，请将该域名也加入目标列表。

目标保存在本地 `config.local.json` 的 `targets` 列表中，并兼容旧配置的 `routes` / `hosts` 字段。存在 `targets` 时以它为准。域名在连接或重连时解析，地址变化后需要重连刷新。

解析顺序为校园 DNS、公网 DoH、本地备用地址表。公网 DoH 在代理联动模式下通过 Clash 请求，在直连模式下直接请求。解析得到的 IPv4 加入校园专用路由：

- **代理联动**：精确域名映射写入生成的 Clash 配置。
- **校园直连**：精确域名临时写入 Windows hosts，使用一个选定 IPv4；断开或恢复时仅删除本次标记的条目。已有同名 hosts 映射会报错，不覆盖用户条目。应用需遵循系统域名解析。

两种模式均不修改系统全局 DNS，也不增加校园默认路由。若某个域名无法解析，日志会保留错误，其他已解析或直接配置为 IP 的目标继续工作。校内专有域名可能没有公网 DNS 记录，公网返回 NXDOMAIN 不等于校园 DNS 中也不存在。

### 可选的本地备用地址表

高级用户可创建 `config.hosts.local.json`，维护已确认的备用 IPv4。该文件只保留在本地，不提交或打包；实时 DNS 优先于备用地址，使用备用表时会记录提示。

```json
{
  "hosts": {
    "node.campus.example": ["192.0.2.10", "192.0.2.11"]
  }
}
```

对备用表中的目标，程序会探测 10022 端口的 SSH 握手，优先选择能响应的节点。探测不提交账号密码；全部超时时保留已有地址供重试。端口和平台账号以学校说明为准，超算账号可能与校园 VPN 账号不同。

## 连接测试与问题处理

“连接测试”访问校园软件站和 Google：联动模式使用本地代理端口，直连模式直接访问。Google 在当前网络无法直连时，外网项可能失败，需结合校园目标的实际访问结果判断，不能仅据此认定 VPN 失败。测试站点也不能代替对自己配置主机的验证。

在解压目录中也可以使用 PowerShell 检查状态或采样：

```powershell
.\Status.ps1
.\Test-Connection.ps1
.\Test-Connection.ps1 -Count 60 -IntervalSeconds 10
```

结果保存在本地 `runtime/checks.csv`。校园 SSH 可按目标的实际端口测试：

```powershell
ssh <主机账号>@<校园IP>
ssh -p 10022 <超算账号>@<校园域名>
.\Test-Hpc.ps1
```

`Test-Hpc.ps1` 仅检查已配置域名地址的 10022 端口 SSH 握手，结果保存在 `runtime/hpc-checks.csv`。

| 情况 | 处理方式 |
| --- | --- |
| 首次准备客户端失败 | 检查网络、7-Zip 和日志；也可手动运行 `Setup.ps1` |
| 未找到 mihomo | 在“代理设置”中选择内核文件；没有运行中的代理时可使用直连 |
| 代理联动检测失败 | 核对规则模式、TUN、配置目录、控制管道和代理端口 |
| 部分域名未解析 | 检查目标拼写和 DNS 日志，必要时维护已确认的本地备用地址 |
| 网卡已连接但主机不可达 | 检查目标是否已配置、地址是否正确，以及服务端口和主机自身状态 |
| 断开后清理失败 | 点击“异常恢复”；不要手动删除其他 VPN 的网卡或路由 |

命令行恢复需在管理员 PowerShell 中执行：

```powershell
.\Recover.ps1
```

恢复仅停止路径和启动时间匹配的本项目 OpenConnect，清理记录的校园路由和临时域名映射，并恢复本项目备份的 Clash 配置。如果全局增强脚本在连接后被另行修改，程序会保留修改并提示手动处理。

## 源码运行与开发

以下步骤面向开发者；从 Releases 下载便携包的用户无需执行。

```powershell
git clone https://github.com/Gingkoleaves/TJ_vpn.git
cd TJ_vpn
.\Test.ps1
.\Build.ps1
.\Setup.ps1
.\TongjiVPN.exe
```

构建需要 Rust stable 和 Windows C++ 链接工具；测试还使用 Windows PowerShell / WinForms。`Setup.ps1` 下载固定版本 OpenConnect，校验 SHA256 后通过 7-Zip 解包。Wintun 在创建接口时加载，网络配置需要管理员权限。

命令行连接需在管理员 PowerShell 中运行：

```powershell
# Clash Verge 联动
.\Connect.ps1

# 没有运行中代理时直连
.\Connect.ps1 -NoClash

# 自定义 Clash Verge 路径
.\Connect.ps1 -ClashDirectory 'C:\your\clash-config' -MihomoPath 'C:\your\verge-mihomo.exe'
```

`Start.cmd` 是代理联动的命令行备用入口。认证时 `authgroup` 留空，账号密码仅在本机输入；命令行连接窗口需要保持运行，Ctrl+C 请求断开。GUI 会自动处理认证组，并使用隐藏的管理员后台。

### 打包与发布

```powershell
.\Package.ps1 -Version 0.3.0-preview.8
```

在已完成构建的干净工作目录运行，输出 ZIP 和 `.zip.sha256` 至本地 `dist/`。同版本输出目录已存在时，脚本会拒绝覆盖；应先备份原输出，或使用新版本号。

GitHub Actions 会在 Windows 上执行自动化测试；[打包工作流](.github/workflows/package.yml) 需手动触发，生成 Actions Artifact，不自动创建 tag 或 GitHub Release。面向用户的下载文件应作为 Release 附件上传，而不是提交 `dist/`。

PowerShell / WinForms 负责 GUI、连接生命周期和 Windows 网络配置，Rust 负责 exe 启动器及 Clash YAML / 增强脚本生成。发布包使用文件白名单，并附 [第三方组件说明](THIRD-PARTY.md)。

## 凭据与恢复设计

- 密码不保存、不作为命令行参数；通过受限本机命名管道传给后台，双方核对进程 ID，传递后清空 GUI 密码框。后台输出先脱敏再写日志。
- 本地配置、备用目标表、日志和运行状态被 Git 忽略，并从发布包排除。
- 独占锁避免启动多个本项目连接；会话网卡使用随机后缀，避免残留同名接口导致重新连接失败。
- 添加与清理路由时核对校园接口身份；学校下发的默认路由不作为校园默认路由安装。
- Clash 候选配置先由 mihomo 校验；加载后恢复原手选代理组，失败时尝试回滚。程序不退出 Clash。
- 本版不提供保存密码或开机免密服务。长期运行、休眠恢复、第二台电脑、IPv6、多因素认证和第三方图书馆数据库仍待验证。

## 官方参考

- [OpenConnect Array 协议](https://www.infradead.org/openconnect/array.html)
- [OpenConnect Windows 构建说明](https://www.infradead.org/openconnect/packages.html)
- [Mihomo DIRECT 出口绑定接口](https://wiki.metacubex.one/config/proxies/direct/)
- [Mihomo DNS 配置](https://wiki.metacubex.one/config/dns/)

本项目非同济大学、Array Networks 或 OpenConnect 官方产品。
