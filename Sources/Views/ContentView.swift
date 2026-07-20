import SwiftUI
import AppKit

/// Tab 选中状态 — 用 ObservableObject 避免 @State 宏依赖
private final class TabState: ObservableObject {
    @Published var selection: Tab = .extensions

    enum Tab: String, CaseIterable {
        case extensions
        case apps
    }
}

/// 主窗口
struct ContentView: View {

    private let extensionVM = ExtensionListViewModel()
    private let appVM = AppListViewModel()
    private let tabState = TabState()

    var body: some View {
        TabView(selection: Binding(
            get: { tabState.selection },
            set: { tabState.selection = $0 }
        )) {
            ExtensionListView(viewModel: extensionVM)
                .tabItem {
                    Label("扩展名", systemImage: "doc.text.magnifyingglass")
                }
                .tag(TabState.Tab.extensions)

            AppListView(viewModel: appVM)
                .tabItem {
                    Label("应用", systemImage: "square.grid.2x2")
                }
                .tag(TabState.Tab.apps)
        }
        .task { OpenlyApp.updateAppIcon() }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didChangeScreenParametersNotification
            )
        ) { _ in OpenlyApp.updateAppIcon() }
        .onReceive(
            DistributedNotificationCenter.default.publisher(
                for: Notification.Name("AppleInterfaceThemeChangedNotification")
            )
        ) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                OpenlyApp.updateAppIcon()
            }
        }
    }
}
