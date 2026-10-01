# 验证记录

日期：2026-10-01；Windows 11，本机 Clash Verge 2.4.2 / Mihomo 1.19.13。

## 本轮已完成

用户原生登录实测：Array 认证成功，Windows 创建 `TongjiVPN`（接口描述 `OpenConnect Tunnel`）。旧版本 hook 因描述匹配错误而退出，尚未完成校园路由。已修复描述识别并加入 4 项回归检查：当前 21 项安全检查、6 项 HTTP 检查、5 项 Rust 检查通过。无校园通路时采样能完整输出校园超时及外网 HTTP 200，不再被 PowerShell NativeCommandError 中断。实际路由及校园访问仍待重新连接验证。

发布验证补充：HTTP 管道解析的 6 项检查通过（包括中文 UTF-8 分块响应）；已只读获取当前 Clash 的手选代理组，未退出或重启 Clash。

| 检查 | 结果 |
|---|---|
| 官方 OpenConnect 9.21 Windows x64 包下载、SHA256 校验与解包 | 通过 |
| 原生 executable --version | array 协议与 Wintun DLL 可用 |
| 原生 executable --protocol=array --authenticate --non-inter | 到达 authgroup 输入阶段；未提交密码 |
| Windows JScript pre-init hook | 通过；未改变路由 |
| PowerShell 文件语法 | 通过 |
| PowerShell 安全检查 | 17 项通过：拒绝默认/非法/保留路由、参数转义、状态原子替换、接口编号复用保护 |
| Rust 测试 | 5 项通过：外网配置保留、重复应用、冲突拒绝、状态/默认路由拒绝、校园 DNS 与网关独立 |
| Rust fmt / clippy | 通过 |
| 从当前实际 Clash YAML 生成候选配置并执行 Mihomo -t | 通过；未应用到运行中的 Clash |
| 生成持久增强 JS 后在 Node 中执行 | 原外网节点和 TUN 保留 |
| 本机 Clash 控制管道、规则模式、TUN、7897 端口 | 通过只读检查 |

## 本轮尚未完成

- Windows 原生客户端实际认证、Wintun 网卡创建与地址配置。
- 原生隧道中的 SSH/软件站访问，以及与外网代理并行访问。
- 原生连接重连、Ctrl+C 清理和强制终止后的真实恢复。
- 连续运行至少 30 分钟、网络切换/休眠恢复。
- 在第二台 Windows PC 上验证便携包。

以上项目需要用户本机输入密码，并保持原生连接运行。未完成前，版本只能作为预发布，不能宣称生产级稳定。

## 前一阶段 WSL 证据（与原生验证区分）

Ubuntu OpenConnect 的 Array 模式将 authgroup 留空后登录成功。经 WSL SOCKS / Clash 访问校园软件站 HTTP 200，同时 Google HTTP 200；用户实际 SSH 登录 user@192.0.2.10 成功。用户后来手动关闭 WSL，校园连接随之失效。这些记录只证明协议/学校账号路径在 Ubuntu 可用，不能证明 Windows 生命周期代码已验证。
