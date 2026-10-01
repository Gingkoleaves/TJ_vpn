# 第三方组件

本仓库的 MIT 许可仅适用于本仓库新增代码，不替代依赖组件的许可。

## 外部下载，不包含在本仓库和 portable ZIP 中

- OpenConnect 9.21：LGPL-2.1，官方项目 https://gitlab.com/openconnect/openconnect ，Windows 包含其上游打包的 GnuTLS 等 DLL 和 Wintun。
- 下载地址：https://gitlab.com/openconnect/openconnect/-/jobs/artifacts/v9.21/raw/openconnect-installer-MinGW64-GnuTLS.exe?job=MinGW64%2FGnuTLS
- 本机取得的 x64 安装包 SHA256：`6ee9e8eb9bc59ef70bb0717df7f99703f8a2ccd11d8e45d58a61f9a2e6ef7d00`。Setup.ps1 固定版本并验证该摘要，再用 7-Zip 解包。
- Wintun 项目：https://www.wintun.net/ 。由上游 OpenConnect 安装包提供。
- 7-Zip：https://www.7-zip.org/ 。由用户安装，不随本仓库打包。
- Clash Verge / Mihomo：使用用户现有安装，不包含用户订阅和代理凭据。

## Rust helper

确切依赖版本固定在 Cargo.lock。直接依赖为 serde_json 和 serde_yaml_ng；完整依赖与 license 元数据可用 `cargo metadata --locked --format-version 1` 查看。源码可从 https://crates.io/ 下载。便携包包含本仓库 Rust helper；重新构建不需要任何个人配置。

CI 中的 actions/checkout 和 dtolnay/rust-toolchain 仅用于构建和检查，不会登录校园网。
# Distributed license texts

The `third-party-licenses/` directory contains license and notice files for the Rust dependencies resolved by Cargo.lock. These are included in the portable ZIP alongside the MIT license for this project. The GUI executable is a Rust launcher; the WinForms panel uses the PowerShell and .NET components provided by Windows.
