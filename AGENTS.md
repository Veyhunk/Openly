# Openly 项目 AI 工作规则

## 启动与进程清理

- 每次安装、启动、UI 验证或重新编译后启动前，先完全退出所有 Openly 相关进程和窗口。
- 清理范围包括 `/Applications/Openly.app`、项目 `.build/Openly.app`、批处理 Receiver、主程序内嵌 Receiver 及其桥接进程。
- 清理后必须确认进程列表为空，再启动唯一一个目标构建；不得让旧进程继续持有旧版本代码或旧路由窗口。
- 安装脚本必须在启动前完成清理，并在无法清零时失败退出。

## 权限与自动验收

- 辅助功能和完全磁盘访问权限由用户在系统设置中手动授权，AI 不能代替用户修改 TCC。
- 进行窗口聚焦、Receiver 接管、Chrome/Edge Profile、浏览器已有窗口或标签组验收前，先提示用户确认：主程序 Openly、Openly Receiver 的辅助功能权限，以及 Chromium Profile 所需的完全磁盘访问权限。
- 用户未完成手动授权时，只执行构建、静态检查和不依赖 TCC 的自动化测试，并明确说明窗口/浏览器验收未完成。
- 每次安装完成都输出人工权限检查提示，不能把 Terminal 或其他进程的权限状态当成 Openly 的权限状态。
- 窗口或浏览器列表异常时，先在干净重启后收集 `log show --last 5m --style compact --predicate 'subsystem == "com.openly.app" && (category == "windows" || category == "browser")'`，再根据 AX 错误码、PID、返回数量和标题判断；不能只凭界面卡片猜测数据来源。

## 窗口和浏览器数据边界

- 应用已有窗口只使用 macOS Accessibility API 的真实 AX 窗口对象；没有权限或 AX 没有返回窗口时显示授权/刷新提示。
- 不生成“窗口 1/2/123”、未命名窗口或其他无法对应真实窗口的占位卡片，不使用 Quartz 窗口列表作为选择器兜底。
- Chromium 的已有窗口和标签组只使用浏览器扩展返回的数据。窗口卡片代表浏览器窗口，窗口内 Tab 只作为数量或标签组信息，不单独转换成窗口卡片。
- 任何窗口选择项都必须能对应到可执行的真实窗口对象，并能在选择后通过 AX 聚焦；无法满足时保留请求并提示原因。

## 键盘焦点

- SwiftUI 路由选择器使用 `FocusState`、`focusScope`、`focusSection`、`onMoveCommand` 和绑定到实际控件的 `onKeyPress`。
- 方向键、Tab 和回车必须作用于真实可聚焦的 TextField 或 Button；不要使用无法确认焦点归属的全局事件拦截器代替 SwiftUI 焦点树。
- 改动后至少运行 `swift build`、`bash scripts/test.sh` 和 `git diff --check`；TCC 相关验收需在用户完成手动授权后进行。
- 窗口排查日志使用 `com.openly.app` 的 `windows` 分类，浏览器桥接日志使用 `browser` 分类；日志只记录排查所需的应用、PID、数量、标题和错误码。
- 新增 Swift 源文件后必须同步检查 `Package.swift` 和显式源文件测试入口（当前为 `scripts/test.sh`），避免主构建通过但自动测试漏编译新代码。
