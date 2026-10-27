# Openly — 开发任务追踪

> 最后更新：2026-07-20
> 每个任务完成后自动 git commit（不 push）


## 原生重设计与打开接管（2026-10-27）

- [x] 共享数据源、有效默认查询、类型别名合并、逐项写入与核验
- [x] 文件类型／应用／打开接管／检查文件原生界面
- [x] 按应用／类型选择接管后缀，预览、接管记录与恢复
- [x] 独立按需接收器、应用缓存、请求排队及失败反馈
- [x] Finder 唤起前台聚焦、应用图标网格与一步执行的高级卡片
- [x] 批量接管统一提交入口：Owner 接收器注册、系统确认、批量核验与结果恢复
- [x] Chrome／Edge 个人资料、新窗口、无痕、新建临时会话
- [x] 浏览器窗口／标签组扩展与 Native Messaging 桥接
- [x] VS Code 窗口路由、通用窗口发现与兼容转发
- [x] 配置导入导出、旧格式读取、文件覆盖检测与清理
- [x] 核心规则测试、隔离系统类型接管／恢复测试、桥接测试
- [ ] 新构建辅助功能授权后的窗口路由端到端验证
- [ ] 浏览器测试个人资料安装扩展后的端到端验证
- [ ] macOS 14 与 Intel 实机兼容验证

当前结果与环境边界见 [实现验证记录](docs/implementation-validation.md)。

---

## 决策日志

| 日期 | 决策 | 理由 |
|------|------|------|
| 2026-07-20 | 产品命名为 **Openly** | 调研 macOS 开源生态命名趋势后选定：-ly 友好型、直指 Finder「打开方式」 |
| 2026-07-20 | TabView 替代 NavigationSplitView | 无-Xcode 环境中 NavigationLink 复杂；TabView 简洁 |
| 2026-07-20 | Binding Helper 模式 | `@Bindable`/`@State` 宏在 CLI 工具链不可用 |
| 2026-07-20 | App 详情用 List 替代 Table | 非 keyPath 版 TableColumn 在 Swift 6 类型推断不兼容 |
| 2026-07-20 | 不安装 Xcode，纯 CLI 构建 | 降低开发环境门槛 |
| 2026-07-20 | SF Symbols 替代 emoji | macOS 原生风格；emoji 跨版本渲染不一致 |
| 2026-07-20 | 去掉 AI 味道 | 避免「Built with X」「智能管理」等措辞 |

---

## Phase 1 — MVP 核心（✅ 已完成）

- [x] 项目骨架 + 数据模型 + 4 个核心 Services
- [x] ExtensionListView + AppListView + BatchOperationView + ContentView
- [x] @main 入口 + 设置面板 + 关于页
- [x] 构建通过（Swift 6.4 + macOS 27 SDK，纯 CLI）

---

## Phase 2 — App 视图增强 + 批量操作（✅ 已完成）

- [x] App 详情页：icns 图标加载、版本号、路径
- [x] BatchOperationView 重写：搜索 → 选择 → 应用 → 结果
- [x] AppInfo 模型扩展：version, iconPath
- [x] App 扫描缓存（5 分钟 TTL + forceRefresh）
- [x] 从 App 详情移除关联
- [x] 替换 App 默认程序（picker sheet）

---

## Phase 3 — 高级特性（✅ 已完成）

- [x] 系统 App 筛选标签：com.apple.* + 路径检测 + Picker 分段控件
- [x] 扩展名描述库扩展：655 个扩展名、405 条中文描述、13 个分类
- [x] xattr 检测与清除：XattrService（com.apple.LaunchServices.OpenWith）
- [x] 导出/导入：ConfigService JSON 格式，含 NSSavePanel/NSOpenPanel 菜单
- [x] 键盘快捷键：Cmd+R 刷新、Cmd+Shift+S 导出、Cmd+Shift+O 导入

---

## Phase 4 — 发布准备（🚧 进行中）

- [x] README.md：功能介绍、安装说明、系统要求
- [x] CHANGELOG.md：Keep a Changelog 格式
- [x] 版本管理：AppVersion 枚举，单一定义
- [ ] 应用图标设计（暂用 SF Symbol）
- [ ] DMG 打包脚本
- [ ] Homebrew Cask formula

---

## 技术债务（✅ 大部分已处理）

- [x] App 扫描结果缓存（AppScanner cacheTTL）
- [x] 键盘快捷键（Cmd+R, Cmd+Shift+S/O）
- [x] 配置文件导入/导出
- [x] xattr 清理支持
- [ ] 单元测试（Models + Services）
- [ ] 错误处理本地化（中英文）

---

## 已知限制

| 限制 | 原因 | 影响 |
|------|------|------|
| 仅 CLI 构建 | 无 Xcode 环境 | 不能用 @State/@Bindable/#Preview |
| 非沙盒 | 需读 `~/Library/Preferences/` | 仅 DMG 分发 |
| SIP 保护 | 系统 App 某些 UTI 被锁定 | Safari/Mail 关联可能不可修改 |
| macOS 14+ | 使用较新 API | 不支持 Ventura 及更早系统 |
| API 版本 | `setDefaultApplication(at:toOpen:)` 是 macOS 27 签名 | 低版本可能不同 |
