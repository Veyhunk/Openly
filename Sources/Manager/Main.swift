import SwiftUI
import AppKit

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
    var routeWindow: NSWindow?
    var store: AppStore?
    let router = RouterModel()
    var isReceiver: Bool { Bundle.main.bundleIdentifier == RoutingRules.receiverID }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(isReceiver ? .accessory : .regular)
        installMenus()
        if !isReceiver { showManager() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !isReceiver { showManager() }; return true
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        router.enqueue(urls)
        if routeWindow == nil {
            let window = makeWindow(title: "用哪个应用打开？", size: NSSize(width: 760, height: 540))
            window.contentView = NSHostingView(rootView: RouteView(model: router))
            window.delegate = self; routeWindow = window
            router.onDismiss = { [weak self] in self?.finishRequest() }
            router.onWillOpen = { [weak self] in self?.routeWindow?.orderOut(nil) }
            router.onFailure = { [weak self] in self?.routeWindow?.makeKeyAndOrderFront(nil); NSApp.activate() }
        }
        routeWindow?.makeKeyAndOrderFront(nil); NSApp.activate()
    }
    func showManager() {
        if managerWindow == nil {
            let store = AppStore(); self.store = store
            let window = makeWindow(title: "Openly", size: NSSize(width: 1120, height: 760))
            window.minSize = NSSize(width: 880, height: 600)
            window.contentView = NSHostingView(rootView: ManagerView(store: store))
            window.delegate = self; managerWindow = window
        }
        managerWindow?.makeKeyAndOrderFront(nil); NSApp.activate()
    }
    func makeWindow(title: String, size: NSSize) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = title; w.isReleasedWhenClosed = false; w.center(); return w
    }
    func finishRequest() {
        if router.next() { routeWindow?.makeKeyAndOrderFront(nil); NSApp.activate(); return }
        routeWindow?.close(); routeWindow = nil
        if isReceiver { NSApp.terminate(nil) }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === routeWindow && router.busy { return false }
        if sender === managerWindow && store?.busy == true { store?.stop = true; return false }
        if sender === routeWindow { router.cancelAll() }
        return true
    }
    func windowWillClose(_ notification: Notification) {
        if let w = notification.object as? NSWindow, w === routeWindow { routeWindow = nil; if isReceiver { NSApp.terminate(nil) } }
        if let w = notification.object as? NSWindow, w === managerWindow { managerWindow = nil; store = nil }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if router.busy || store?.busy == true {
            store?.stop = true
            let alert = NSAlert(); alert.messageText = "正在完成当前操作"; alert.informativeText = "后续关联修改已停止，当前操作完成后可退出。"; alert.runModal()
            return .terminateCancel
        }
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func installMenus() {
        let main = NSMenu()
        let appMenu = NSMenu(); let appItem = NSMenuItem(); appItem.submenu = appMenu; main.addItem(appItem)
        appMenu.addItem(withTitle: "关于 Openly", action: #selector(about), keyEquivalent: "").target = self
        appMenu.addItem(.separator()); appMenu.addItem(withTitle: "退出 Openly", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = NSMenu(title: "文件"); let item = NSMenuItem(title: "文件", action: nil, keyEquivalent: ""); item.submenu = file; main.addItem(item)
        let exp = file.addItem(withTitle: "导出配置…", action: #selector(exportConfig), keyEquivalent: "S"); exp.target = self
        let imp = file.addItem(withTitle: "导入配置…", action: #selector(importConfig), keyEquivalent: "O"); imp.target = self
        let edit = NSMenu(title: "编辑"); let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: ""); editItem.submenu = edit; main.addItem(editItem)
        for (title, action, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] { edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key) }
        let view = NSMenu(title: "视图"); let vi = NSMenuItem(title: "视图", action: nil, keyEquivalent: ""); vi.submenu = view; main.addItem(vi)
        view.addItem(withTitle: "搜索", action: #selector(focusSearch), keyEquivalent: "f").target = self
        view.addItem(withTitle: "刷新", action: #selector(refresh), keyEquivalent: "r").target = self
        NSApp.mainMenu = main
    }
    @objc func focusSearch() { if routeWindow?.isKeyWindow == true { router.focusRequest += 1 } else { store?.searchRequest += 1 } }
    @objc func refresh() { Task { await store?.refresh() } }
    @objc func exportConfig() { store?.exportConfig() }
    @objc func importConfig() { store?.importConfig() }
    @objc func about() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Openly", .applicationVersion: "2.0", .credits: NSAttributedString(string: "打开方式，一目了然")]) }
}
