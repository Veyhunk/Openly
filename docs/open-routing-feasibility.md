# 打开方式接管与精准启动：可行性简报

> 2026-10-27 · 基于项目静态检查及官方接口资料；性能数值为建议验收目标，尚未进行原型实测。

## 结论

**总体可行，建议采用“按需启动的原生路由器 + 可选应用适配器”。** 基础接管、应用选择、Chrome Profile / 新窗口 / 无痕和 VS Code 新窗口可优先验证；精准选择已有窗口、标签组属于增强能力，需要对应应用接口或扩展配合。

扫描应用声明只能得到文件格式候选，账号、窗口、分组需要单独查询。当前 Openly 已有扫描与关联修改能力，尚需补充处理器注册、打开事件接收、转发队列和精准启动适配。

## 能力判断

| 需求 | 可行性与最佳实现方向 |
|---|---|
| 接管文件打开方式 | 高。声明支持的文件类型，经用户启用后设为默认处理器，收到事件后显示应用选择器，再显式转发给目标应用。声明支持与设置默认是两个步骤。[1] |
| 接管系统浏览器打开 | 高。注册 HTTP/HTTPS 处理能力，经系统确认设置默认浏览器。覆盖通过系统默认浏览器打开的链接；应用内网页和显式指定浏览器的调用仍走其自身路径。[1] |
| Chrome 指定账号 | 高，但应定义为 **Profile（浏览器个人资料）**。使用 Profile 启动参数；名称与目录映射缓存，失效时重选。同一 Profile 内多个网站登录账号由网站自身控制。多 Profile 已运行时的路由必须实测。[2] |
| Chrome 新窗口、无痕 | 高。以命令行参数或浏览器原生脚本接口启动；验证浏览器未运行、已运行、多 Profile 和策略禁用无痕的组合。无痕会话具有独立登录状态。 |
| Chrome 指定已有窗口 | 中高。轻量方案可验证 macOS 脚本字典按窗口 ID 创建标签，首次需要自动化授权；若同时要求准确的 Profile 归属、窗口和分组，优先统一使用浏览器扩展，避免混合结果无法对应。 |
| 加入已打开标签组 | 高，需扩展。通过 `tabs` / `tabGroups` 查询窗口和组，创建标签后加入指定组；目标在同一 Profile 中解析，提交时复查是否仍存在。无痕内操作需用户额外允许扩展运行。[3] |
| Edge | 可复用 Chromium 扩展核心逻辑，但安装位置、扩展 ID、Profile 路径与启动参数仍有差异。按“共享实现 + 少量配置”验证通过后一起交付。[4] |
| VS Code 新窗口 / 最近窗口 | 高。官方 CLI 提供 `--new-window`、`--reuse-window`；后者指向最近活动窗口。[5] |
| VS Code 任意指定窗口 | 中。官方 CLI 未提供通用窗口 ID 选择器。建议由运行在各窗口中的本地 UI 扩展注册会话及工作区，经本地 IPC 在对应窗口调用打开文件 API；需验证空窗口、同工作区多窗口和失效会话。[5][6] |

浏览器无痕参数、Profile 参数与 macOS 脚本支持应作为版本化适配能力维护。选择器只展示已验证可用的组合。

## 冷启动与后台功耗方案

推荐将运行路径拆开：

```text
系统打开事件 → 小型 AppKit 接收器 → 缓存候选 / 路由规则
                                  → 紧凑选择器 → 显式转发 → 退出
管理界面：用户主动打开时启动，负责配置与完整扫描
高级目标：用户展开窗口 / 分组时，按需查询适配器
```

- **默认按需运行。** 接收器作为独立、可被 Launch Services 启动的 app bundle；由系统唤起，队列处理完成后退出。管理窗口及其数据模型不进入打开请求的关键路径。
- **先展示，再补数据。** 缓存应用图标、候选与 Profile 信息；扫描放在管理界面或显式刷新，启动时仅校验所选目标。窗口和分组只在用户展开时查询。
- **空闲以退出为目标。** 基础模式不需要常驻托盘、定时扫描和轮询。可选“快速响应”模式仅保留小接收器及事件循环，关闭后销毁选择器；是否值得常驻由实测决定。
- **高级桥接单独核算。** Chrome Native Messaging 由扩展发起连接，原生程序不能直接凭空唤醒休眠扩展；持久连接还会维持 Service Worker 存活。[7] 因此“无常驻 + 随时获取所有 Profile 实时窗口”需要先验证唤醒协议。优先尝试按需扩展中转页与短连接；其焦点扰动、目标 Profile 定位及关闭行为必须通过原型。若体验不合格，提供可选增强常驻模式并明确资源成本。
- **参考 CC Switch 的原则。** 其轻量模式销毁主窗口并按需重建。[8] Openly 可借鉴资源生命周期；原生应用仍需实测唤醒次数和功耗，释放窗口内存不等于整个应用零耗电。

建议验收起点：在约定测试机上，已安装且完成首次授权后，进程退出状态到选择器可交互 **P95 ≤ 300 ms**；常驻模式 **P95 ≤ 100 ms**。分别记录首次安装启动、进程冷启动、系统重启后启动；目标浏览器或编辑器的启动时间单独统计。基础模式空闲时 Openly 相关进程应退出；增强模式记录空闲 10 分钟的 CPU、唤醒、内存和能耗，确认没有周期性轮询。数值须经原型校准后才能承诺。

## 必须验证的边界

1. **接管与恢复：** 保存原默认值；停用时只恢复当前仍指向 Openly 的项目。已签名 app bundle 的类型声明保持稳定，新类型支持经发布或已验证的注册方案扩展。
2. **可靠转发：** 明确指定目标应用，排除自身，避免重新调用默认打开而形成循环；目标失效时回到选择器。多链接排队并用请求 ID 防重复，确认接收后再退出。
3. **精确性：** Profile、窗口、标签组 ID 均带会话范围；目标关闭或 Profile 删除时重新选择。VS Code 的“最近活动窗口”和“指定窗口”分别呈现。
4. **接口选择：** 浏览器高级能力优先官方扩展 API。Chrome 136 起默认用户数据目录限制远程调试，CDP 路线不适合接管日常 Profile。[9] 扩展桥接按需授权并校验请求来源，URL 与路径通过参数传递。

## 推荐推进顺序

先做一个最小原型：HTTP/HTTPS 接管、缓存选择器、Chrome Profile / 新窗口 / 无痕、VS Code 新窗口，并测冷启动与空闲资源。通过后，再验证浏览器扩展的“Profile → 窗口 → 分组”端到端路由和休眠唤醒；Edge 通过共享适配测试后并入。VS Code 指定窗口作为独立扩展能力验证。

**最关键的技术风险是高级目标的低功耗发现与准确唤醒。** 基础接管已有标准系统路径；窗口与分组接口也具备能力，但组合体验和性能必须用原型证明。

## 依据

1. Apple：[文档类型声明](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundledocumenttypes)、[接收打开事件](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/application(_:open:))、[设置 URL Scheme 默认应用](https://developer.apple.com/documentation/appkit/nsworkspace/setdefaultapplication(at:toopenurlswithscheme:completion:))。
2. Chromium：[用户数据与 Profile 目录](https://chromium.googlesource.com/chromium/src.git/+/HEAD/docs/user_data_dir.md)。
3. Chrome：[Tabs API](https://developer.chrome.com/docs/extensions/reference/api/tabs)、[Tab Groups API](https://developer.chrome.com/docs/extensions/reference/api/tabGroups)、[无痕扩展模式](https://developer.chrome.com/docs/extensions/reference/manifest/incognito)。
4. Microsoft：[Chrome 扩展迁移到 Edge](https://learn.microsoft.com/en-us/microsoft-edge/extensions/developer-guide/port-chrome-extension)。
5. VS Code：[官方命令行参数](https://code.visualstudio.com/docs/configure/command-line)。
6. VS Code：[扩展 API](https://code.visualstudio.com/api/references/vscode-api)。指定窗口 IPC 为基于窗口内 API 的工程方案，尚待原型验证。
7. Chrome：[Native Messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)、[Service Worker 生命周期](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle)。
8. CC Switch：[官方轻量模式发布说明](https://github.com/farion1231/cc-switch/blob/main/docs/release-notes/v3.13.0-zh.md)。
9. Chrome：[远程调试参数变更](https://developer.chrome.com/blog/remote-debugging-port)。
