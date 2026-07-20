import SwiftUI
import AppKit

/// 主窗口 — 启动时加载图标并监听外观切换
struct ContentView: View {

    private let extensionVM = ExtensionListViewModel()
    private let appVM = AppListViewModel()

    var body: some View {
        TabView {
            ExtensionListView(viewModel: extensionVM)
                .tabItem {
                    Label("扩展名", systemImage: "doc.text.magnifyingglass")
                }

            AppListView(viewModel: appVM)
                .tabItem {
                    Label("应用", systemImage: "square.grid.2x2")
                }
        }
        .task {
            OpenlyApp.updateAppIcon()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didChangeScreenParametersNotification
            )
        ) { _ in
            OpenlyApp.updateAppIcon()
        }
        .onReceive(
            DistributedNotificationCenter.default.publisher(
                for: Notification.Name("AppleInterfaceThemeChangedNotification")
            )
        ) { _ in
            // 延迟一点让系统先切换
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                OpenlyApp.updateAppIcon()
            }
        }
    }
}
