import SwiftUI
import AppKit

struct PermissionSettingsView: View {
    @NativeState private var refreshToken = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("权限设置").font(.title2)
                    Text("Openly 根据你选择的打开方式访问浏览器资料和窗口。授权后点击“刷新检测”，再重新打开链接即可生效。")
                        .foregroundStyle(.secondary)
                }
                ForEach(OpenlyPermissionKind.allCases) { kind in
                    PermissionRow(kind: kind, refreshToken: refreshToken)
                }
                GroupBox("应用身份") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("管理程序和 Openly Receiver 是两个独立的 macOS 应用身份，权限需要分别出现在系统设置中。下面的 Receiver 状态会在它处理一次打开请求后更新。")
                        Text("完全磁盘访问权限：/Applications/Openly.app，以及其中的 Contents/Helpers/Openly Receiver.app")
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("刷新检测") { refreshToken += 1 }
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .id(refreshToken)
        .navigationTitle("权限设置")
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard let window = notification.object as? NSWindow, window === NSApp.keyWindow else { return }
            refreshReceiverPermission()
        }
        .task { await refreshReceiverPermissionAsync() }
    }

    func refreshReceiverPermission() {
        OpenlyPermissionService.requestReceiverAccessibilityProbe()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { refreshToken += 1 }
    }

    func refreshReceiverPermissionAsync() async {
        _ = await ReceiverService.start()
        OpenlyPermissionService.requestReceiverAccessibilityProbe()
        try? await Task.sleep(for: .milliseconds(300))
        refreshToken += 1
    }
}

private struct PermissionRow: View {
    let kind: OpenlyPermissionKind
    let refreshToken: Int

    var body: some View {
        let state = OpenlyPermissionService.state(for: kind)
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: state == .granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(state == .granted ? .green : .orange)
                    Text(kind.title).font(.headline)
                    Spacer()
                    Text(state.label).foregroundStyle(state == .granted ? .green : .secondary)
                }
                Text(kind.purpose).foregroundStyle(.secondary)
                if kind == .fullDiskAccess {
                    Text("用于读取 Chrome / Edge 的 Local State；缺少时会回退为默认个人资料。")
                        .font(.caption).foregroundStyle(.secondary)
                } else if kind == .receiverAccessibility {
                    Text("macOS 辅助功能列表通常不能从主应用包内直接选中附属 Receiver；请用下面的 Finder 按钮显示它，再将 Openly Receiver.app 拖入系统设置列表。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("用于读取已有窗口和执行窗口聚焦；默认打开、新窗口和无痕窗口不依赖此权限。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("打开系统设置") { OpenlyPermissionService.openSystemSettings(for: kind) }
                        .buttonStyle(.bordered)
                    if kind == .receiverAccessibility {
                        Button("在 Finder 中显示 Receiver") { OpenlyPermissionService.revealReceiverInFinder() }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id("\(kind.rawValue)-\(refreshToken)")
    }
}
