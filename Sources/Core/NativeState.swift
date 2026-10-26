import SwiftUI

// SDK 27 同时导出 State 宏和属性包装器。显式类型别名使用稳定包装器，
// 保留 SwiftUI 状态生命周期，同时兼容没有 SwiftUIMacros 插件的 CLI 工具链。
typealias NativeState<Value> = SwiftUI.State<Value>

typealias NativeFocus<Value: Hashable> = SwiftUI.FocusState<Value>
