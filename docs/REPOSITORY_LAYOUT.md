# 仓库布局

当前源码与便携包采用以下目录约定。已发布的 `v0.3.0-preview.8` 仍使用旧布局，发布附件与标签不作替换。

```text
.
├── StartGUI.cmd              # GUI 备用双击入口
├── Start.cmd                 # 命令行备用入口
├── app/                      # GUI、连接、配置准备、诊断与恢复入口
├── scripts/                  # 共享 PowerShell/C# 组件与 OpenConnect hook
├── src/                      # Rust 配置生成器与 GUI exe 启动器
├── config/
│   ├── config.example.json   # 无个人目标的配置模板
│   └── package-files.txt     # 发布包文件白名单
├── tools/                    # 测试、构建、打包与发布包验证
├── tests/                    # 模拟环境中的回归检查
├── docs/                     # 开发、布局、验证记录与发布说明
├── third-party-licenses/     # 第三方许可证
├── Cargo.toml / Cargo.lock
├── README.md / LICENSE / THIRD-PARTY.md
└── .github/workflows/        # Windows CI 与手动打包
```

构建后生成的 `TongjiVPN.exe` 位于根目录，便于双击启动。运行时通过脚本位置定位项目根目录，不依赖终端当前工作目录。新启动器优先加载 `app/Gui.ps1`，同时兼容旧包的根目录 `Gui.ps1`。

## 本地文件

以下文件和目录不属于受版本控制的源码，不应提交或发布：

| 路径 | 用途 |
| --- | --- |
| `config.local.json` | 用户校园目标和本地 VPN 参数 |
| `connection.local.json` | GUI 模式与代理设置 |
| `config.hosts.local.json` | 可选的本地备用地址 |
| `runtime/` | 会话状态、恢复记录、日志与测试临时文件 |
| `vendor/`、`downloads/` | 下载并校验的 OpenConnect 组件 |
| `target/`、`bin/` | Rust 构建产物 |
| `dist/` | 本地 ZIP、校验文件与打包暂存目录 |
| `resources/` | 本地参考资料 |

整理目录不迁移用户配置或恢复记录，避免影响已有会话与清理逻辑。不要用清理构建目录的操作删除 `runtime/` 中仍需要的恢复记录。

## 发布包

发布包保留根目录 exe 和 cmd 双击入口，包含 `app/`、`scripts/`、配置模板、用户文档和第三方许可证；不包含构建工具、测试源码或本地用户数据。

`config/package-files.txt` 明确列出要发布的脚本与文档；新增运行依赖时同时更新该清单。Rust 二进制和第三方许可证由打包工具单独加入。使用 `tools/Test-Package.ps1` 验证 ZIP 内容、SHA256、配置模板和解压后的实际启动能力。
