import AppKit
import ApplicationServices

struct AppWindow: Identifiable {
    let id: Int
    let title: String
    let element: AXUIElement
    let pid: pid_t
}
@MainActor enum WindowAccess {
    static var trusted: Bool { AXIsProcessTrusted() }
    static var receiverStatusText: String {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Openly Receiver.app")
        if !FileManager.default.fileExists(atPath: helper.path) { return "当前构建没有内嵌 Openly Receiver，请使用完整 Openly.app。" }
        if !trusted { return "当前管理程序尚未获辅助功能权限；Receiver 仍需单独授权。" }
        return "管理程序权限可用；Receiver 权限需在系统列表中单独确认。"
    }
    static func openSettings() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
    static func windows(appID: String) -> [AppWindow] {
        var result: [AppWindow] = []
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: appID)
        OpenlyLog.windows.info("AX query start appID=\(appID, privacy: .public) trusted=\(trusted, privacy: .public) processes=\(runningApps.count, privacy: .public)")
        for running in runningApps {
            let app = AXUIElementCreateApplication(running.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 2.0)
            var value: CFTypeRef?
            var error = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
            if error != .success { OpenlyLog.windows.error("AX windows attribute failed appID=\(appID, privacy: .public) pid=\(running.processIdentifier, privacy: .public) error=\(error.rawValue, privacy: .public)") }
            if error == .cannotComplete {
                AXUIElementSetMessagingTimeout(app, 2.0)
                error = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
                OpenlyLog.windows.info("AX windows retry appID=\(appID, privacy: .public) pid=\(running.processIdentifier, privacy: .public) error=\(error.rawValue, privacy: .public)")
            }
            guard error == .success, let windows = value as? [AXUIElement] else { continue }
            OpenlyLog.windows.info("AX windows attribute returned appID=\(appID, privacy: .public) pid=\(running.processIdentifier, privacy: .public) count=\(windows.count, privacy: .public)")
            for window in windows {
                var title: CFTypeRef?, subrole: CFTypeRef?
                // kAXWindowsAttribute is already defined by Apple as the
                // application's window collection. Do not require a specific
                // subrole: Electron apps may omit AXStandardWindowSubrole on
                // secondary document windows.
                let titleError = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
                let subroleError = AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
                guard let title = title as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    OpenlyLog.windows.debug("AX window skipped appID=\(appID, privacy: .public) pid=\(running.processIdentifier, privacy: .public) titleError=\(titleError.rawValue, privacy: .public) subroleError=\(subroleError.rawValue, privacy: .public)")
                    continue
                }
                let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard normalizedTitle.range(of: #"^(?:未命名窗口|窗口|.+窗口)\s*\d+$"#, options: .regularExpression) == nil else {
                    OpenlyLog.windows.info("AX window skipped ambiguous title appID=\(appID, privacy: .public) pid=\(running.processIdentifier, privacy: .public) title=\(normalizedTitle, privacy: .public)")
                    continue
                }
                OpenlyLog.windows.info("AX window accepted appID=\(appID, privacy: .public) pid=\(running.processIdentifier, privacy: .public) title=\(normalizedTitle, privacy: .public) subrole=\(String(describing: subrole), privacy: .public)")
                result.append(.init(id: result.count, title: normalizedTitle, element: window, pid: running.processIdentifier))
            }
        }
        OpenlyLog.windows.info("AX query result appID=\(appID, privacy: .public) count=\(result.count, privacy: .public) titles=\(result.map(\.title).joined(separator: " | "), privacy: .public)")
        return result
    }
    static func newWindowAction(appID: String) -> AXUIElement? {
        guard trusted, let running = NSRunningApplication.runningApplications(withBundleIdentifier: appID).first else { return nil }
        let app = AXUIElementCreateApplication(running.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 0.2)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &value) == .success, let value else { return nil }
        let menu = unsafeDowncast(value, to: AXUIElement.self)
        let names: Set<String> = ["New Window", "新建窗口", "新窗口", "新增視窗", "新增窗口"]
        var visits = 0
        func find(_ element: AXUIElement, depth: Int) -> AXUIElement? {
            visits += 1
            guard depth < 5, visits < 160 else { return nil }
            var title: CFTypeRef?, enabled: CFTypeRef?, children: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
            AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabled)
            if let title = title as? String, names.contains(title), enabled as? Bool == true { return element }
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success, let items = children as? [AXUIElement] {
                for item in items { if let result = find(item, depth: depth + 1) { return result } }
            }
            return nil
        }
        return find(menu, depth: 0)
    }
    static func createWindow(appID: String) async throws {
        let before = windows(appID: appID)
        guard let action = newWindowAction(appID: appID) else { throw OpenlyError("应用当前没有可用的新窗口动作") }
        NSRunningApplication.runningApplications(withBundleIdentifier: appID).first?.activate()
        guard AXUIElementPerformAction(action, kAXPressAction as CFString) == .success else { throw OpenlyError("新建窗口失败") }
        for _ in 0..<20 {
            if let new = windows(appID: appID).first(where: { w in !before.contains { CFEqual($0.element, w.element) } }) { try await focus(new); return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw OpenlyError("未确认新窗口，请检查应用后重试")
    }
    static func focus(_ window: AppWindow) async throws {
        guard trusted else { throw OpenlyError("请先授予辅助功能权限") }
        guard let app = NSRunningApplication(processIdentifier: window.pid), !app.isTerminated else { throw OpenlyError("目标应用已退出") }
        AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        app.activate()
        let raised = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        guard raised == .success else { throw OpenlyError("无法激活目标窗口，请刷新窗口列表") }
        AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        let axApp = AXUIElementCreateApplication(window.pid)
        for _ in 0..<12 {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value) == .success,
               let value, CFEqual(value, window.element), NSWorkspace.shared.frontmostApplication?.processIdentifier == window.pid { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw OpenlyError("目标窗口未获得焦点，请重新选择")
    }
}
