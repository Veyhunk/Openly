import SwiftUI

struct PreferencesView: View {
    @NativeState private var dockIconVisible = OpenlyPreferences.dockIconVisible
    @NativeState private var residentBackground = OpenlyPreferences.residentBackground
    @NativeState private var autoOpenSingleOption = OpenlyPreferences.autoOpenSingleOption

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
            }
            Section("打开选择") {
                Toggle("只有一种打开方式时直接打开", isOn: $autoOpenSingleOption)
                    .onChange(of: autoOpenSingleOption) { OpenlyPreferences.autoOpenSingleOption = autoOpenSingleOption }
                Text("存在多个应用窗口、浏览器 Profile、标签组或无痕选项时，仍会显示选择窗口。")
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
