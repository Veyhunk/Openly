import SwiftUI

/// 主窗口
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
    }
}
