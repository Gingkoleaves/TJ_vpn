# 开发与验证

普通用户使用 [GitHub Release 便携包](https://github.com/Gingkoleaves/TJ_vpn/releases)，不需要构建工具。本文针对当前源码布局；已发布 preview.8 包的 PowerShell 入口仍位于根目录。

## 环境

- Windows x64、Windows PowerShell 5.1、WinForms。
- Rust stable，含 rustfmt 和 clippy。
- Windows C++ 链接工具。
- 手动准备 OpenConnect 时需要 7-Zip。

```powershell
git clone https://github.com/Gingkoleaves/TJ_vpn.git
cd TJ_vpn
.\tools\Test.ps1
.\tools\Build.ps1
.\app\Setup.ps1
.\TongjiVPN.exe
```

`tools/Test.ps1` 检查 PowerShell 语法、目录依赖、模式选择、路由安全、DNS、凭据传递、GUI 构建和 Rust 测试，并运行 fmt/clippy。使用模拟数据，不登录校园网或改变真实路由。仅检查 PowerShell 部分时可加 `-SkipRust`。

`app/Setup.ps1` 下载固定版本 OpenConnect，校验 SHA256 后解包，不执行系统级安装器。首次 GUI 连接也会自动准备客户端。

## 命令行入口

以下连接与恢复命令需要管理员 PowerShell；诊断不需要主动更改网络配置。

```powershell
# Clash Verge 联动
.\app\Connect.ps1

# 没有运行中代理时直连
.\app\Connect.ps1 -NoClash

# 自定义 Clash Verge 路径
.\app\Connect.ps1 -ClashDirectory 'C:\your\clash-config' -MihomoPath 'C:\your\verge-mihomo.exe'

.\app\Status.ps1
.\app\Test-Connection.ps1
.\app\Test-Hpc.ps1
.\app\Recover.ps1
```

`Start.cmd` 是代理联动的备用入口。命令行认证时 authgroup 留空，账号密码在本机输入；连接窗口需保持运行，Ctrl+C 请求断开。`Doctor.ps1` 主要检查 Clash 联动环境，不作为直连环境是否正常的唯一依据。

GUI 设置和用户配置仍保存在项目根目录，运行数据仍保存在 `runtime/`。目录说明见 [仓库布局](REPOSITORY_LAYOUT.md)。

## 打包

完成测试和构建后，以待发布版本号打包，例如：

```powershell
.\tools\Package.ps1 -Version 0.3.0-preview.9
.\tools\Test-Package.ps1 -PackagePath .\dist\tongji-openconnect-0.3.0-preview.9-windows-x64.zip
```

上例是下一版本的打包示例，不代表 preview.9 已发布。同版本暂存目录已存在时脚本拒绝覆盖，应先备份旧输出或使用新版本号。ZIP 和 `.zip.sha256` 输出至被 Git 忽略的 `dist/`。

发布文件白名单见 [package-files.txt](../config/package-files.txt)。依赖脚本移动后必须同步更新入口引用和白名单，并验证解压后的 exe。不要将本地配置、日志、订阅、账号或备用目标表加入清单。

## CI 与发布

GitHub Actions 的 [测试工作流](https://github.com/Gingkoleaves/TJ_vpn/blob/main/.github/workflows/test.yml) 在 push/PR 时运行 Windows 检查。[打包工作流](https://github.com/Gingkoleaves/TJ_vpn/blob/main/.github/workflows/package.yml) 手动触发，运行测试、构建、启动器检查、打包和 ZIP 验证，上传 Actions Artifact；不自动创建 tag 或 GitHub Release。

发布顺序：更新版本说明与打包版本号，测试、构建、打包并验证；提交并推送；创建对应的 annotated tag；在 GitHub Release 上传 ZIP 与 SHA256。预发布保留 pre-release 标记，并注明未验证范围。

已发布版本的 tag 与附件应保持固定。文档更新可单独提交，不重新覆盖旧 ZIP。本次目录调整也不会替换 `v0.3.0-preview.8` 的附件。

实际校园登录、目标服务、长时间运行和网络切换需在本机验证。测试时保持已有代理连接，账号密码不写入脚本或聊天。验证结果记录在 [VALIDATION.md](VALIDATION.md)。
