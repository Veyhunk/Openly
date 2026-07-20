import SwiftUI

/// Openly — macOS 文件打开方式管理工具
/// Slogan: 打开方式，一目了然
@main
struct OpenlyApp: App {

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 960, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
        }
    }
}

/// 设置面板 — macOS 14 兼容
struct SettingsView: View {

    var body: some View {
        TabView {
            Form {
                Text("设置项将在后续版本中添加")
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .padding()
            .tabItem {
                Label("通用", systemImage: "gearshape")
            }

            aboutView
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
        }
        .frame(width: 400, height: 300)
    }

    private var aboutView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Openly")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("打开方式，一目了然")
                .font(.body)
                .foregroundStyle(.secondary)

            Text("版本 \(AppVersion.display)")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            Text("macOS 文件打开方式管理工具")
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
        .padding(32)
    }
}
