import SwiftUI
import UniformTypeIdentifiers

/// Openly — macOS 文件打开方式管理工具
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

            // 文件菜单
            CommandGroup(after: .newItem) {
                Button("导出配置…") { exportConfig() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("导入配置…") { importConfig() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            // 视图菜单
            CommandGroup(before: .toolbar) {
                Button("刷新") { refreshAll() }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
    }

    // MARK: - 菜单操作

    private func exportConfig() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Openly_config_\(dateStamp()).json"
        panel.title = "导出文件关联配置"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            let reader = LaunchServicesReader()
            let service = ConfigService()
            do {
                let assocs = try await reader.readAllAssociations()
                try await service.exportAssociations(from: assocs, to: url)
            } catch {
                print("[Openly] 导出失败: \(error)")
            }
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.title = "导入文件关联配置"
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.urls.first else { return }

        Task {
            let service = ConfigService()
            let writer = LaunchServicesWriter()
            do {
                let config = try await service.readConfig(from: url)
                let result = await service.importAssociations(from: config, writer: writer)
                print("[Openly] 导入完成: \(result.success)/\(result.total)")
            } catch {
                print("[Openly] 导入失败: \(error)")
            }
        }
    }

    private func refreshAll() {
        // 通过通知或直接重建视图触发刷新
        // 实际刷新由各视图的 ViewModel.task 处理
    }

    private func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f.string(from: Date())
    }

    /// 根据当前系统外观加载对应图标
    static func updateAppIcon() {
        let isDark = NSApp.effectiveAppearance.name == .darkAqua
            || NSApp.effectiveAppearance.name == .vibrantDark

        let iconName = isDark ? "AppIcon-dark" : "AppIcon"

        guard let url = ResourceHelper.url(forResource: iconName, withExtension: "icns"),
              let iconImage = NSImage(contentsOf: url) else {
            return
        }

        NSApp.applicationIconImage = iconImage
    }
}

// MARK: - 设置面板

struct SettingsView: View {

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("通用", systemImage: "gearshape") }

            aboutTab
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 420, height: 320)
    }

    private var generalTab: some View {
        Form {
            Section("数据") {
                LabeledContent("当前版本", value: AppVersion.display)
                LabeledContent("代号", value: AppVersion.codename)
            }

            Section("提示") {
                Text("修改关联后无需重启，系统立即生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("系统内置 App（如 Safari、Mail）的某些关联受系统保护，可能无法修改。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var aboutTab: some View {
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
