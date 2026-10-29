import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct OpenlyMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = OpenlyDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor final class OpenlyDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var managerWindow: NSWindow?
    var store: AppStore?
    var routeModels: [UUID: RouterModel] = [:]
    var routeWindows: [UUID: NSWindow] = [:]
    var statusItem: NSStatusItem?
    var lightweightWorkItem: DispatchWorkItem?
    var isReceiver: Bool { Bundle.main.bundleIdentifier == RoutingRules.receiverID || Bundle.main.object(forInfoDictionaryKey: "OpenlyReceiver") as? Bool == true }
    var lightModeEnabled: Bool { OpenlyPreferences.lightweightModeEnabled }
    var residentBackground: Bool { OpenlyPreferences.residentBackground }
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(isReceiver || !OpenlyPreferences.dockIconVisible ? .accessory : .regular)
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged), name: OpenlyPreferences.didChange, object: nil)
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:reply:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }
    @objc func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: value) else { return }
        application(NSApp, open: [url])
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenus()
        configureStatusItem()
        if !isReceiver { showManager() }
        else { DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, !self.lightModeEnabled, self.routeModels.isEmpty else { return }
            NSApp.terminate(nil)
        } }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !isReceiver { showManager() } else { routeWindows.keys.forEach { showChooser($0) } }
        return true
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        let valid = urls.filter { $0.isFileURL || ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
        guard !valid.isEmpty else { return }
        guard OpenlyPreferences.takeoverEnabled else {
            Task { await openOriginal(valid) }
            return
        }
        let id = UUID(); let router = RouterModel(); router.enqueue(valid); routeModels[id] = router
        let window = makeWindow(title: "用哪个应用打开？", size: NSSize(width: 760, height: 520))
        window.contentView = NSHostingView(rootView: RouteView(model: router))
        window.minSize = NSSize(width: 680, height: 520); window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]; window.delegate = self; routeWindows[id] = window
        router.onDismiss = { [weak self] in self?.finishRequest(id) }
        router.onWillOpen = { [weak self] in self?.routeWindows[id]?.orderOut(nil) }
        router.onFailure = { [weak self] in self?.showChooser(id) }
        showChooser(id)
    }
    func showChooser(_ id: UUID) {
        guard let window = routeWindows[id], let router = routeModels[id] else { return }
        if PerformanceProbe.enabled { window.orderFront(nil); DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.terminate(nil) }; return }
        window.deminiaturize(nil); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); window.orderFrontRegardless()
        DispatchQueue.main.async { [weak window] in NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps]); window?.makeKeyAndOrderFront(nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak window] in guard let window, window.isVisible, !window.isKeyWindow, !router.busy else { return }; window.level = .floating; window.orderFrontRegardless() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak window] in if let window { PerformanceProbe.recordFocus(window) } }
    }
    func finishRequest(_ id: UUID) { routeWindows[id]?.close(); routeWindows.removeValue(forKey: id); routeModels.removeValue(forKey: id); if isReceiver && !lightModeEnabled && routeModels.isEmpty { NSApp.terminate(nil) } }
    func showManager() {
        lightweightWorkItem?.cancel(); lightweightWorkItem = nil
        if managerWindow == nil {
            let store = AppStore(); self.store = store; let window = makeWindow(title: "Openly", size: NSSize(width: 1120, height: 760)); window.minSize = NSSize(width: 880, height: 600); window.contentView = NSHostingView(rootView: ManagerView(store: store)); window.delegate = self; managerWindow = window
        }
        applyActivationPolicy()
        managerWindow?.makeKeyAndOrderFront(nil); NSApp.activate()
    }
    func configureStatusItem() {
        guard !isReceiver else { return }
        if residentBackground && managerWindow == nil {
            if statusItem == nil { statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength) }
            statusItem?.button?.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Openly")
            let menu = NSMenu()
            menu.addItem(withTitle: "打开 Openly", action: #selector(openFromStatusItem), keyEquivalent: "").target = self
            menu.addItem(.separator())
            let takeover = menu.addItem(withTitle: "打开接管", action: #selector(toggleTakeover), keyEquivalent: "")
            takeover.state = OpenlyPreferences.takeoverEnabled ? .on : .off; takeover.target = self
            let light = menu.addItem(withTitle: "轻量模式：窗口关闭后自动启用", action: nil, keyEquivalent: ""); light.isEnabled = false
            menu.addItem(.separator())
            menu.addItem(withTitle: "退出 Openly", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q").target = NSApp
            statusItem?.menu = menu
        } else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem); self.statusItem = nil }
        }
    }
    func makeWindow(title: String, size: NSSize) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = title; w.isReleasedWhenClosed = false
        if title == "Openly", let value = UserDefaults.standard.string(forKey: "Openly.managerFrame") {
            let frame = NSRectFromString(value)
            if frame.width >= 880, frame.height >= 600, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) { w.setFrame(frame, display: false) } else { w.center() }
        } else { w.center() }
        return w
    }
    func routeID(for window: NSWindow) -> UUID? { routeWindows.first { $0.value === window }?.key }
    func windowDidBecomeKey(_ notification: Notification) { if let window = notification.object as? NSWindow, routeID(for: window) != nil { window.level = .normal } }
    func windowDidResignKey(_ notification: Notification) { if let window = notification.object as? NSWindow, routeID(for: window) != nil { window.level = .normal } }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let id = routeID(for: sender) { guard routeModels[id]?.busy != true else { return false }; routeModels[id]?.cancelAll(); return true }
        if sender === managerWindow, store?.busy == true { store?.stop = true; return false }; return true
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if let id = routeID(for: window) { routeModels[id]?.cancelAll(); routeWindows.removeValue(forKey: id); routeModels.removeValue(forKey: id); if isReceiver && !lightModeEnabled && routeModels.isEmpty { NSApp.terminate(nil) } }
        if window === managerWindow {
            UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "Openly.managerFrame")
            managerWindow = nil; store = nil
            scheduleLightweightTransition()
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if routeModels.values.contains(where: { $0.busy }) || store?.busy == true { store?.stop = true; let alert = NSAlert(); alert.messageText = "正在完成当前操作"; alert.informativeText = "当前打开或关联修改完成后才能退出。"; alert.runModal(); return .terminateCancel }
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !residentBackground }
    func installMenus() {
        let main = NSMenu(); let appMenu = NSMenu(); let appItem = NSMenuItem(); appItem.submenu = appMenu; main.addItem(appItem); appMenu.addItem(withTitle: "关于 Openly", action: #selector(about), keyEquivalent: "").target = self; appMenu.addItem(.separator()); appMenu.addItem(withTitle: "退出 Openly", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = NSMenu(title: "文件"); let item = NSMenuItem(title: "文件", action: nil, keyEquivalent: ""); item.submenu = file; main.addItem(item); file.addItem(withTitle: "导出配置…", action: #selector(exportConfig), keyEquivalent: "S").target = self; file.addItem(withTitle: "导入配置…", action: #selector(importConfig), keyEquivalent: "O").target = self
        let edit = NSMenu(title: "编辑"); let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: ""); editItem.submenu = edit; main.addItem(editItem); for (title, action, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] { edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key) }
        let view = NSMenu(title: "视图"); let vi = NSMenuItem(title: "视图", action: nil, keyEquivalent: ""); vi.submenu = view; main.addItem(vi); view.addItem(withTitle: "刷新", action: #selector(refresh), keyEquivalent: "r").target = self; view.addItem(withTitle: "偏好设置…", action: #selector(openPreferences), keyEquivalent: ",").target = self; NSApp.mainMenu = main
    }
    @objc func openFromStatusItem() { showManager() }
    @objc func toggleTakeover() { OpenlyPreferences.takeoverEnabled.toggle(); configureStatusItem() }
    @objc func openPreferences() { showManager(); store?.page = "偏好设置" }
    @objc func preferencesChanged() { applyActivationPolicy(); configureStatusItem() }
    func applyActivationPolicy() {
        guard !isReceiver else { NSApp.setActivationPolicy(.accessory); return }
        let window = managerWindow
        let shouldRestoreFocus = window?.isVisible == true && window?.isKeyWindow == true
        let policy: NSApplication.ActivationPolicy = OpenlyPreferences.dockIconVisible && managerWindow != nil ? .regular : .accessory
        NSApp.setActivationPolicy(policy)
        if shouldRestoreFocus {
            DispatchQueue.main.async { [weak window] in
                guard let window, window.isVisible else { return }
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
    func originalAppID(for url: URL, state: LocalState) -> String? {
        let key: String?
        if url.isFileURL, let type = UTType(filenameExtension: url.pathExtension) { key = type.identifier }
        else if let scheme = url.scheme { key = "scheme:\(scheme.lowercased())" }
        else { key = nil }
        guard let key else { return nil }
        if key.hasPrefix("scheme:"), let browser = OpenlyPreferences.lastBrowserAppID, AssociationService.appURL(browser) != nil {
            return browser
        }
        let current = AssociationService.current(key)
        if let record = state.records.first(where: { $0.id == key && RoutingRules.isReceiverID($0.targetAppID) }),
           let previous = record.previousAppID, !RoutingRules.isReceiverID(previous) { return previous }
        if !RoutingRules.isReceiverID(current) { return current }
        return nil
    }
    func openOriginal(_ urls: [URL]) async {
        let state = (try? StateFiles.read()) ?? LocalState()
        var grouped: [String: [URL]] = [:]
        var fallback: [URL] = []
        for url in urls {
            if let id = originalAppID(for: url, state: state), AssociationService.appURL(id) != nil { grouped[id, default: []].append(url) }
            else if let current = currentAppID(for: url), !RoutingRules.isReceiverID(current) { fallback.append(url) }
        }
        do {
            for (id, values) in grouped {
                guard let appURL = AssociationService.appURL(id) else { continue }
                let config = NSWorkspace.OpenConfiguration(); config.activates = true
                _ = try await NSWorkspace.shared.open(values, withApplicationAt: appURL, configuration: config)
            }
            if !fallback.isEmpty {
                let config = NSWorkspace.OpenConfiguration(); config.activates = true
                for url in fallback { _ = try await NSWorkspace.shared.open(url, configuration: config) }
            }
        } catch {
            // 关闭接管时保持系统原生打开路径，单次失败不重新唤起选择器。
        }
    }
    func currentAppID(for url: URL) -> String? {
        if url.isFileURL, let type = UTType(filenameExtension: url.pathExtension) { return AssociationService.current(type.identifier) }
        if let scheme = url.scheme { return AssociationService.current("scheme:\(scheme.lowercased())") }
        return nil
    }
    func scheduleLightweightTransition() {
        lightweightWorkItem?.cancel(); lightweightWorkItem = nil
        guard !isReceiver, residentBackground else { applyActivationPolicy(); configureStatusItem(); return }
        let delay = OpenlyPreferences.lightweightDelaySeconds
        if delay <= 0 { applyActivationPolicy(); configureStatusItem(); return }
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.managerWindow == nil, self.residentBackground else { return }
            self.applyActivationPolicy(); self.configureStatusItem(); self.lightweightWorkItem = nil
        }
        lightweightWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
    @objc func refresh() { Task { await store?.refresh() } }
    @objc func exportConfig() { store?.exportConfig() }
    @objc func importConfig() { store?.importConfig() }
    @objc func about() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Openly", .applicationVersion: AppVersion.display, .credits: NSAttributedString(string: "打开方式，一目了然")]) }
}
