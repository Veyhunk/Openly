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
    static func openSettings() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
    static func windows(appID: String) -> [AppWindow] {
        guard trusted else { return [] }
        var result: [AppWindow] = []
        for running in NSRunningApplication.runningApplications(withBundleIdentifier: appID) {
            let app = AXUIElementCreateApplication(running.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 0.2)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success, let windows = value as? [AXUIElement] else { continue }
            for window in windows {
                var role: CFTypeRef?, title: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &role)
                guard role as? String == kAXStandardWindowSubrole else { continue }
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
                result.append(.init(id: result.count, title: (title as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "未命名窗口 \(result.count + 1)", element: window, pid: running.processIdentifier))
            }
        }
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
