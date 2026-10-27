# Openly

**打开方式，一目了然。** 原生 macOS 文件关联管理与打开接管工具，支持 macOS 14 及以上。

## 功能

- **文件类型与应用管理**：搜索、分类、系统／第三方筛选、排序、多选、类型别名预览、修改结果核验。
- **打开接管**：按应用或类型批量选择后缀，接管网页链接，保存接管前应用并提供恢复。
- **轻量选择器**：系统打开事件按需唤起；首屏为应用图标网格，默认只显示支持当前格式的应用，下一步以卡片直接选择打开方式；支持返回与连续请求排队。
- **轻量模式**：关闭管理窗口后释放界面资源并保留快速唤起能力；可选择显示菜单栏图标，从菜单栏或再次启动 Openly 重新打开管理界面。
- **Chrome / Edge**：个人资料、新窗口、无痕、新建临时会话；通过配套扩展选择已有窗口与标签组。
- **VS Code**：新窗口、最近活动窗口、聚焦指定窗口后复用打开。
- **其他多窗口应用**：辅助功能窗口查询与聚焦后兼容打开；识别原生“新建窗口”菜单动作。
- **配置与排查**：JSON 导出／导入预览、恢复本工具保存的修改前设置、单文件 OpenWith 覆盖检测与清理。

## 构建与使用

要求 Swift 6 工具链、macOS Command Line Tools；无需额外 Swift 包。

```bash
# 交互菜单：方向键 / 数字快捷键
./build.command

# 编译并打包管理程序、接收器与浏览器桥接
python3 scripts/package-app.py release

# 打开构建产物
open .build/Openly.app
```

打包产物为 `.build/Openly.app`。日常使用前将它放入“应用程序”，再在“打开接管”页启用所需类型。修改会先显示实际系统类型及连带后缀；失败和待验证项目保留逐项结果。

管理界面和接收器使用独立应用身份。系统将所选类型交给内嵌接收器；用户选定目标后显式转发，避免再次调用系统默认处理器。管理页扫描结果与恢复记录保存在 `~/Library/Application Support/Openly/state.json`。

### 高级打开能力

- 指定窗口：在 macOS“隐私与安全性 → 辅助功能”中允许 **Openly Receiver**。接收器位于 `Openly.app/Contents/Helpers/`。
- 浏览器窗口与标签组：按 [扩展安装说明](BrowserExtension/README.md) 加载配套扩展，在打开接管页填写扩展 ID。移动应用后重新连接，以更新本机桥接路径。
- 新建临时会话：每次使用独立的新用户数据目录打开当前内容。
- 通用窗口兼容：应用可能自行决定最终打开位置；专用适配优先使用其明确的窗口接口。

## 验证

```bash
swift build
bash scripts/test.sh
node scripts/test-browser-extension.cjs

# 在项目 .build/checks 内注册独立测试类型，验证接管与恢复
python3 scripts/package-app.py debug
bash scripts/test.sh --integration

# Release 接收器进程冷启动测量（需先打开管理页建立应用缓存）
python3 scripts/package-app.py release
swiftc -parse-as-library scripts/benchmark.swift -o .build/checks/benchmark
.build/checks/benchmark
```

`test.sh` 直接编译生产代码并执行断言，兼容缺少 XCTest 模块的 Command Line Tools 环境。测试失败返回非零退出码。浏览器扩展测试覆盖窗口枚举、标签组路由、目标失效、部分失败与无效请求；Native Messaging 测试覆盖一次性令牌、重放拒绝和过期请求。

[验证记录](docs/implementation-validation.md) 区分自动化、实机与待验证项目。

## 发布打包

```bash
./scripts/project-launcher.sh package
./scripts/project-launcher.sh dmg
```

本地构建使用 ad-hoc 签名。面向外部分发时需使用开发者证书签名并公证。

## 代码入口

| 目录 | 职责 |
|---|---|
| `Sources/Core` | 文件类型规划、系统关联读写、本地恢复记录 |
| `Sources/Manager` | 原生管理界面、操作预览与结果、应用入口 |
| `Sources/Routing` | 接收器选择器、窗口能力、浏览器与 VS Code 转发 |
| `Sources/Services` | 应用扫描与内置描述库 |
| `BridgeHost` / `BrowserExtension` | 按需浏览器扩展桥接 |
| `Tests` / `scripts` | 自动化验证、原生打包与启动器 |

设计依据：[原生界面设计](docs/native-ui-redesign.md)、[接管技术报告](docs/open-routing-feasibility.md)。
