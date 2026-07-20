# Openly — macOS 文件打开方式管理工具

**Slogan:** 打开方式，一目了然

## 项目概述

Openly 是一款原生 macOS 应用，帮助用户直观地管理和切换文件扩展名的默认打开方式。灵感来源于 Finder 的「打开方式」(Open With) 菜单。

## 产品命名

**Openly** — 经过对 2025-2026 年 macOS 开源工具生态的命名趋势研究后选定：
- **含义直接**：来自 Finder「打开方式」(Open With)，用户秒懂
- **命名模式**：采用 -ly 友好型后缀（同 Maccy 20K⭐、Clipy 等明星项目范式）
- **中文自然**：「打开方式」四字完美对应
- **SF Symbol**：`arrow.up.forward.app` 天然契合

其他候选：Handlr, Relay, Tether, Mate（详见调研报告）

## 核心功能
1. **按 App 管理后缀** — 查看某个 App 关联了哪些扩展名
2. **按后缀选择 App** — 查看某个扩展名当前由哪个 App 打开，并可更换
3. **清除关联** — 解除扩展名与 App 的绑定
4. **批量关联** — 一次性将多个扩展名关联到同一个 App
5. **内置常见后缀格式描述** — 中文描述（如 .psd → "Adobe Photoshop 文档"）
6. **系统原始后缀推荐程序筛选** — 区分系统原生 App (com.apple.*) 与第三方 App

## 技术栈
- **语言**: Swift 6.4
- **UI**: SwiftUI（原生控件，SF Symbols 6，Sequoia 设计语言）
- **最低系统**: macOS 14 (Sonoma)
- **架构**: MVVM + @Observable + Swift Concurrency（actor Services）
- **构建**: SPM (Swift Package Manager)，支持纯 CLI 构建（无 Xcode）
- **分发**: DMG + Homebrew Cask

## 构建环境

### 当前环境
- **macOS**: 27.0.0 (Darwin)
- **Swift**: 6.4 (swiftlang-6.4.0.25.4)
- **SDK**: MacOSX27.0.sdk
- **工具链**: Command Line Tools only（**无 Xcode**）
- **构建命令**: `swift build`

### ⚠️ 无 Xcode 约束与解决方案

SwiftUI 的 `@State`、`#Preview` 等宏依赖 Xcode 工具链中的 `SwiftUIMacros` / `PreviewsMacros` 插件，CLI 环境不可用。

**解决方案（Binding Helper 模式）**：
```swift
// ❌ 不能使用（需要 Xcode 宏插件）
@State private var searchQuery: String = ""
@Bindable var viewModel: ExtensionListViewModel

// ✅ 替代方案：ViewModel 中提供 Binding 计算属性
var searchQueryBinding: Binding<String> {
    Binding(get: { self.searchQuery }, set: { self.searchQuery = $0 })
}
// 视图中使用: TextField("搜索", text: viewModel.searchQueryBinding)
```

**可用的宏**（来自 Command Line Tools）：
- `@Observable` — Observation 框架宏 ✅
- `@Environment` — SwiftUI 属性包装器 ✅

**不可用的宏**（需要 Xcode）：
- `@State` — SwiftUI 宏 ❌
- `@Bindable` — Observation 宏（部分功能） ❌
- `#Preview` — Previews 宏 ❌
- `@AppStorage` / `@SceneStorage` — SwiftUI 宏 ❌

## 关键 API（实战验证）

### 读取当前关联
- 读取 `~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist`
- 解析 `LSHandlers` 数组，每个元素含 `LSHandlerContentType`(UTI)、`LSHandlerRoleAll`(Bundle ID)
- 备用：`LSCopyDefaultRoleHandlerForContentType()`（macOS 12 已废弃）

### 写入/设置默认 App
```swift
// ⚠️ macOS 27 实际 API（与旧文档不同！）
try await NSWorkspace.shared.setDefaultApplication(
    at: appURL,
    toOpen: utType        // 注意：是 toOpen，不是 toOpenContentType
)
```
- 该 API 是 `async throws`，无需 completion handler
- 旧文档中的 `toOpenContentType:completionHandler:` 在 macOS 27 已不存在
- 废弃: `LSSetDefaultRoleHandlerForContentType()` (macOS 12 已废弃)

### 扫描 App 支持的类型
- 读取每个 App Bundle 的 `Contents/Info.plist` → `CFBundleDocumentTypes`
- `CFBundleDocumentTypes` 包含: `CFBundleTypeExtensions`, `CFBundleTypeName`, `CFBundleTypeRole`, `LSHandlerRank`

### 系统 App 判断
- Bundle ID 前缀 `com.apple.*` → 系统原生 App
- App 路径在 `/System/` 下 → 系统 App

## 数据流
```
读取:
  com.apple.launchservices.secure.plist
    → 解析 LSHandlers → [FileAssociation]
    → UTI → 扩展名列表 (UTType.tags[.filenameExtension])
    → 合并 App 扫描结果 (AppScanner)
    → ExtensionDescriptionDB 补全描述和分类
    → 展示

写入:
  用户选择 扩展名 + App
    → 扩展名 → UTI (UTType API)
    → App Bundle ID → App URL (NSWorkspace.urlForApplication)
    → NSWorkspace.setDefaultApplication(at:toOpen:)
    → 刷新 LSHandlers
```

## 限制和注意事项
1. `NSWorkspace.setDefaultApplication(at:toOpen:)` 是 macOS 27 最新 API，低版本需适配
2. 系统内置 App (Safari, Mail, Notes 等) 的某些 UTI 受 SIP 保护，可能无法覆盖
3. 单文件 xattr 覆盖 (`com.apple.LaunchServices.OpenWith`) 优先级高于全局 LSHandlers
4. 需要读取 `~/Library/Preferences/com.apple.LaunchServices/` 目录，非沙盒 App 可以访问
5. 修改 LSHandlers 后 Launch Services 自动生效，无需手动重启
6. **无 Xcode 环境**：必须避免 `@State`/`#Preview`/`@Bindable`，使用 Binding Helper 模式

## 目录结构
```
Sources/
├── App/                         # @main 入口 + Settings
│   └── OpenlyApp.swift
├── Models/                      # 数据模型
│   └── FileAssociation.swift    # FileAssociation, ExtensionInfo, AppInfo
├── Services/                    # 核心业务服务 (actor 隔离)
│   ├── LaunchServicesReader     # 读取 LSHandlers plist
│   ├── LaunchServicesWriter     # NSWorkspace.setDefaultApplication
│   ├── AppScanner               # 扫描 /Applications 的 Info.plist
│   └── ExtensionDescriptionDB   # 500+ 后缀描述 JSON
├── ViewModels/                  # MVVM ViewModel (@Observable)
│   ├── ExtensionListViewModel   # 扩展名列表状态 + Binding helpers
│   └── AppListViewModel         # App 列表状态 + Binding helpers
├── Views/                       # SwiftUI 视图
│   ├── ContentView              # TabView 主窗口
│   ├── ExtensionListView        # Table + 搜索 + 筛选 + 分类
│   ├── AppListView              # 侧栏 App 列表 + 详情
│   └── BatchOperationView       # 批量操作面板
└── Resources/
    └── extension_descriptions.json  # 236 条分类后缀描述
```

## 设计规范

### macOS 27 / Sequoia 设计语言
- **原生控件优先** — 使用 SwiftUI 标准控件 (Table, List, Picker, Button)，不做过度自定义
- **毛玻璃材质** — 侧边栏使用 `.sidebar` 材质，内容区纯白/暗色背景
- **SF Symbols 6** — 所有图标使用 SF Symbols，保持系统一致性
- **间距系统** — 遵循 Apple HIG 8pt 栅格 (4, 8, 12, 16, 20, 24, 32)
- **字体层级** — 标题 .title2，正文 .body，辅助 .caption，不使用自定义字体
- **动画克制** — 使用 .spring() 默认动画，避免弹跳过猛
- **色彩克制** — 仅使用系统色 (AccentColor, .secondary, .tertiary)
- **TableView 风格** — `.tableStyle(.inset(alternatesRowBackgrounds: true))`

### macOS 14 兼容 API 注意事项
```swift
// ❌ macOS 15+ 才可用
Tab("通用", systemImage: "gearshape") { content }

// ✅ macOS 14 兼容
content.tabItem { Label("通用", systemImage: "gearshape") }
```

### 常见坑
```swift
// ❌ 三元运算符类型推断失败
.foregroundStyle(app.isSystemApp ? .secondary : .blue)
// ✅ 显式类型
.foregroundStyle(app.isSystemApp ? Color.secondary : Color.blue)
```

## 编码规范
- 使用 Swift Concurrency (async/await)，避免回调
- ViewModel 使用 @Observable 宏 (Swift 6)
- 服务层使用 actor，标记 @MainActor 用于 UI 相关
- Views 通过 ViewModel 的 `xxxBinding` 属性获取双向绑定（不用 @Bindable）
- 所有系统调用做好错误处理，用 throws
- 中文注释 + 英文代码标识符
- 产品名称统一使用 "Openly"
