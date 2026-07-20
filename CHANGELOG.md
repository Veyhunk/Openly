# Openly 更新日志

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)。

---

## [1.0.0] — 2026-07-20

### 新增
- 扩展名视图：表格展示所有已知扩展名及其默认打开 App
- 搜索、分类筛选、系统/第三方/未关联过滤
- App 视图：按已安装 App 浏览，查看每个 App 管理的格式
- App 详情：图标、版本号、路径信息
- 批量操作：多选扩展名 → 统一分配到一个 App
- 为扩展名选择默认 App，支持搜索可用 App 列表
- 清除扩展名关联（恢复未绑定状态）
- 内置 236 条常见后缀描述，分 12 大分类（文本、代码、图像、视频、音频、文档、压缩、网页、字体、可执行、数据库、3D/设计）
- 系统原生 App 标识（com.apple.*）+ Apple 图标标记
- 设置面板（关于页面）
- 纯命令行构建支持（Swift 6.4 + macOS 27 SDK，无需 Xcode）

### 已知限制
- 系统锁定类型（Safari/Mail 默认关联）可能无法覆盖
- 纯 CLI 构建不支持 @State/@Bindable 宏，需用 Binding Helper 模式
- 仅 macOS 14+ 可用

---

[1.0.0]: https://github.com/user/openly/releases/tag/v1.0.0
