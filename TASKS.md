# Openly — 开发任务追踪

> 最后更新：2026-07-20
> 每个任务完成后自动 git commit（不 push）

---

## 📋 决策日志

| 日期 | 决策 | 理由 |
|------|------|------|
| 2026-07-20 | 产品命名为 **Openly** | 调研 2025-2026 macOS 开源生态命名趋势后选定：-ly 友好型、直指 Finder「打开方式」、中英文皆佳 |
| 2026-07-20 | 放弃 NavigationSplitView 改用 TabView | 侧边栏导航在当前无-Xcode 环境中与 NavigationLink 配合复杂；TabView 简洁且 macOS 原生 |
| 2026-07-20 | 自行实现 Binding Helper 模式 | `@Bindable`/`@State` 宏在 CLI 工具链不可用；ViewModel 提供 `xxxBinding` 计算属性替代 |
| 2026-07-20 | App 详情用 List 替代 Table | 非 keyPath 版 TableColumn 在 Swift 6 闭包类型推断不兼容；List 更可靠 |
| 2026-07-20 | 不安装 Xcode，纯 CLI 构建 | 环境仅 Command Line Tools；项目适配此约束，降低开发环境门槛 |
| 2026-07-20 | 图标只用 SF Symbols，禁用 emoji | 保持 macOS 原生风格；emoji 在不同系统版本渲染不一致，显得不专业 |
| 2026-07-20 | 去掉产品中的 AI 味道 | 避免「Built with X」「智能管理」等措辞；界面文案直接务实，像人写的 |

---

## Phase 1 — MVP 核心（✅ 已完成）

- [x] 项目骨架搭建（SPM + Swift 6 + macOS 14 target）
- [x] 数据模型（FileAssociation, AppInfo, ExtensionInfo）— 3 个 struct
- [x] LaunchServicesReader — 读取 `com.apple.launchservices.secure.plist`
- [x] LaunchServicesWriter — `NSWorkspace.setDefaultApplication(at:toOpen:)`（经实测确认 API 名）
- [x] AppScanner — 扫描 `/Applications` + `/System/Applications` + `~/Applications`
- [x] ExtensionDescriptionDB — 236 条常见后缀中英文描述，按 12 大分类组织
- [x] ExtensionListView — Table 表格 + 搜索 + 分类下拉 + 系统/第三方/未关联筛选
- [x] AppListView — 左侧 App 列表 + 右侧扩展名详情，支持移除关联
- [x] BatchOperationView — 多选扩展名 → 批量操作入口
- [x] ContentView — TabView 主窗口（扩展名 / 应用）
- [x] OpenlyApp — @main 入口 + Settings 面板
- [x] 构建通过 ✅ — `swift build` 成功，二进制 1.7MB
- [x] 适配无 Xcode 构建环境
- [x] .gitignore 配置（排除 .build/）

### Phase 1 构建过程中解决的问题

1. **API 名修正**: 文档中的 `toOpenContentType:` 在 macOS 27 实际为 `toOpen:`
2. **无 Xcode 宏限制**: 绕过 `@State`/`@Bindable`/`#Preview`，采用 Binding Helper 模式
3. **类型推断冲突**: `HierarchicalShapeStyle` vs `Color` → 使用 `Color.secondary` 等显式类型
4. **macOS 15 API 兼容**: `Tab(_:systemImage:)` 不可用 → 改用 `.tabItem { Label() }`
5. **TableColumn 闭包**: 非 keyPath 版在 Swift 6 中类型推断问题 → App 详情改用 List
6. **actor 方法调用**: `descDB.batchInfo()` 等需要 `await`

---

## Phase 2 — App 视图增强 + 批量操作（🚧 进行中）

- [x] App 详情页完善：显示 App 图标（icns 加载）、版本号、路径
- [x] BatchOperationView 重写：搜索 App → 选择目标 → 应用 → 结果展示
- [x] AppInfo 模型扩展：version, iconPath 字段
- [ ] 清除关联：无关联扩展名单独展示并支持一键清除
- [ ] 支持从 App 详情中添加新扩展名关联
- [ ] App 扫描性能优化（缓存结果）

---

## Phase 3 — 高级特性（待开始）

- [ ] 系统原生 App 筛选标签优化（com.apple.* 检测 + Apple 图标标记）
- [ ] 完善后缀描述库（补充缺失条目，目标 500+）
- [ ] 单文件 xattr 覆盖检测与清除（`com.apple.LaunchServices.OpenWith`）
- [ ] 导出/导入配置文件（JSON/YAML 格式）
- [ ] 撤销/重做支持

---

## Phase 4 — 发布准备（待开始）

- [ ] 中文本地化完善（.strings 文件）
- [ ] 应用图标设计（1024x1024 icns）
- [ ] DMG 打包脚本（create-dmg 或 node-appdmg）
- [ ] Homebrew Cask formula
- [ ] README.md 含截图、安装说明、功能列表

---

## 已知限制

| 限制 | 原因 | 影响 |
|------|------|------|
| 仅 CLI 构建 | 无 Xcode 环境，SwiftUI 宏插件缺失 | 不能使用 @State/@Bindable/#Preview |
| 非沙盒 | 需读 `~/Library/Preferences/` | 不能上架 Mac App Store（可 DMG 分发） |
| SIP 保护 | 系统 App 某些 UTI 被锁定 | Safari/Mail 关联可能无法覆盖 |
| macOS 14+ | 使用了 .foregroundStyle(.quaternary) 等较新 API | 不支持 Ventura 及更早系统 |
| API 版本差异 | `setDefaultApplication(at:toOpen:)` 是 macOS 27 API | 低版本可能签名不同，需适配 |

---

## 技术债务

- [ ] 补齐 `LSHandlers` 写入后的 Launch Services 通知机制（当前依赖手动刷新）
- [ ] 添加单元测试（Models + Services）
- [ ] 性能优化：App 扫描结果缓存（目前每次刷新都扫描）
- [ ] 错误处理本地化（当前英文）
- [ ] 全局快捷键支持（⌘R 刷新等）
