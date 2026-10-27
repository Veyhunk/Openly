import SwiftUI

struct PreferencesView: View {
    @NativeState private var dockIconVisible = OpenlyPreferences.dockIconVisible
    @NativeState private var residentBackground = OpenlyPreferences.residentBackground
    @NativeState private var autoOpenSingleOption = OpenlyPreferences.autoOpenSingleOption
    @NativeState private var lightweightDelaySeconds = OpenlyPreferences.lightweightDelaySeconds
    @NativeState private var advancedRoutingMode = OpenlyPreferences.advancedRoutingMode

    var body: some View {
        Form {
            Section("窗口与后台") {
                Toggle("在 Dock 中显示 Openly", isOn: $dockIconVisible)
                    .onChange(of: dockIconVisible) { OpenlyPreferences.dockIconVisible = dockIconVisible }
                Toggle("关闭窗口后继续在后台运行", isOn: $residentBackground)
                    .onChange(of: residentBackground) { OpenlyPreferences.residentBackground = residentBackground }
                VStack(alignment: .leading, spacing: 5) {
                    Label("轻量模式自动启用", systemImage: "leaf")
                    Text(residentBackground ? "常驻后台开启时，关闭管理窗口会释放界面资源，保留快速接管能力；菜单栏图标会随窗口关闭自动出现。" : "关闭窗口后 Openly 会彻底退出，不保留后台接管进程。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
                Picker("进入轻量模式", selection: $lightweightDelaySeconds) {
                    Text("立即").tag(0.0)
                    Text("10 秒后").tag(10.0)
                    Text("30 秒后").tag(30.0)
                    Text("1 分钟后").tag(60.0)
                }
                .onChange(of: lightweightDelaySeconds) { OpenlyPreferences.lightweightDelaySeconds = lightweightDelaySeconds }
                .disabled(!residentBackground)
                Text("延迟期间可以再次启动 Openly，窗口会立即恢复并取消进入轻量模式。")
                    .font(.caption).foregroundStyle(.secondary)
                    .disabled(!residentBackground)
            }
            Section("打开选择") {
                Toggle("只有一种打开方式时直接打开", isOn: $autoOpenSingleOption)
                    .onChange(of: autoOpenSingleOption) { OpenlyPreferences.autoOpenSingleOption = autoOpenSingleOption }
                Text("存在多个应用窗口、浏览器 Profile、标签组或无痕选项时，仍会显示选择窗口。")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("启用高级打开方式页面", isOn: $advancedRoutingMode)
                    .onChange(of: advancedRoutingMode) { OpenlyPreferences.advancedRoutingMode = advancedRoutingMode }
                Text("将应用列表与打开方式合并到同一页，适合经常在多个应用和窗口之间切换。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("菜单栏图标") {
                Label("自动显示", systemImage: "menubar.arrow.up.rectangle")
                Text("菜单栏图标不单独配置：常驻后台开启且管理窗口关闭时显示，打开管理窗口后自动隐藏。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 680, alignment: .leading)
        .padding(24)
        .navigationTitle("偏好设置")
    }
}
