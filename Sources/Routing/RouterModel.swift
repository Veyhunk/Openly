import SwiftUI
import Observation
import AppKit

@MainActor @Observable
final class RouterModel {
    var urls: [URL] = []
    var queue: [[URL]] = []
    var apps: [AppInfo] = []
    var selectedAppID: String?
    var search = ""
    var focusRequest = 0
    var profile = "Default"
    var profiles: [BrowserProfile] = []
    private var supportedIDs = Set<String>()
    var mode = "default"
    var windowID: Int?
    var browserWindowID: Int?
    var groupID: Int?
    var windows: [AppWindow] = []
    var genericNewWindow = false
    var snapshot = BrowserSnapshot(windows: [], groups: [])
    var busy = false
    var loadingTargets = false
    var error: String?
    var status = ""
    var allowUnsupported = false
    var onDismiss: (() -> Void)?
    var onWillOpen: (() -> Void)?
    var onFailure: (() -> Void)?
    var bridgeIDs: [String: String] = [:]
    private var targetTask: Task<Void, Never>?
    private var generation = 0
    var selectedApp: AppInfo? { apps.first { $0.id == selectedAppID } }
    var chromium: Bool { selectedAppID.map(BrowserService.isChromium) == true }
    var vscode: Bool { selectedAppID == "com.microsoft.VSCode" || selectedAppID == "com.microsoft.VSCodeInsiders" }
    var candidates: [AppInfo] { apps.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }.sorted { a,b in
        let ca = supports(a), cb = supports(b)
        if ca != cb { return ca }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    } }
    func supports(_ app: AppInfo) -> Bool { supportedIDs.contains(app.id) }
    func updateCompatibility() {
        supportedIDs = Set(apps.filter { app in
            let schemes = app.supportedSchemes ?? ((Bundle(path: app.path)?.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]]) ?? []).flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
            return urls.allSatisfy { url in url.isFileURL ? app.supportedExtensions.contains(url.pathExtension.lowercased()) : schemes.contains(url.scheme ?? "") }
        }.map(\.id))
    }
    func enqueue(_ values: [URL]) {
        let valid = values.filter { $0.isFileURL || ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
        guard !valid.isEmpty else { return }
        if urls.isEmpty { urls = Array(NSOrderedSet(array: valid)) as? [URL] ?? valid; loadCache() }
        else { queue.append(valid) }
    }
    func loadCache() {
        do { let state = try StateFiles.read(); apps = state.apps; bridgeIDs = state.bridgeIDs; updateCompatibility() }
        catch { self.error = error.localizedDescription }
        if apps.isEmpty {
            status = "首次使用，正在读取应用…"
            Task {
                let found = await AppScanner().scanAllApps()
                apps = found.filter { ![RoutingRules.receiverID, RoutingRules.managerID].contains($0.id) }
                updateCompatibility(); status = ""
            }
        }
    }
    func next() -> Bool {
        resetTarget()
        if queue.isEmpty { urls = []; return false }
        urls = queue.removeFirst(); updateCompatibility(); return true
    }
    func cancelAll() { targetTask?.cancel(); queue = []; urls = [] }
    func resetTarget() {
        targetTask?.cancel(); generation += 1; selectedAppID = nil; mode = "default"; profile = "Default"
        windows = []; snapshot = .init(windows: [], groups: []); error = nil; search = ""; allowUnsupported = false
    }
    func appChanged() {
        targetTask?.cancel(); generation += 1; loadingTargets = false
        mode = "default"; windowID = nil; browserWindowID = nil; groupID = nil
        snapshot = .init(windows: [], groups: []); allowUnsupported = false
        profiles = selectedAppID.map(BrowserService.profiles) ?? []
        profile = profiles.first?.id ?? "Default"
        refreshWindows()
    }
    func refreshWindows() { windows = selectedAppID.map(WindowAccess.windows) ?? []; windowID = nil; genericNewWindow = !chromium && !vscode && selectedAppID.flatMap { WindowAccess.newWindowAction(appID: $0) } != nil }
    func profileChanged() { targetTask?.cancel(); generation += 1; loadingTargets = false; snapshot = .init(windows: [], groups: []); browserWindowID = nil; groupID = nil }
    func loadBrowserTargets() {
        guard let app = selectedApp, let extID = bridgeIDs[app.id] else { error = "请先在打开接管页连接扩展"; return }
        targetTask?.cancel(); generation += 1; let version = generation; let profile = profile
        loadingTargets = true; error = nil
        targetTask = Task {
            do {
                let data = try await BrowserBridge.request(app: app, profile: profile, extensionID: extID, payload: ["action": "list"])
                let value = try JSONDecoder().decode(BrowserSnapshot.self, from: data)
                guard generation == version else { return }
                snapshot = value; loadingTargets = false; onFailure?()
            } catch {
                guard generation == version else { return }
                loadingTargets = false; self.error = error.localizedDescription; onFailure?()
            }
        }
    }
    var canOpen: Bool {
        guard let app = selectedApp, !busy, !loadingTargets, supports(app) || allowUnsupported else { return false }
        if mode == "window" { return windowID != nil }
        if mode == "browserWindow" { return browserWindowID != nil }
        return true
    }
    func openSelected() async {
        guard let app = selectedApp, canOpen else { return }
        busy = true; error = nil
        defer { busy = false }
        let items = urls
        do {
            guard FileManager.default.fileExists(atPath: app.path) else { throw OpenlyError("应用已移动或删除，请重新选择") }
            onWillOpen?()
            if mode == "browserWindow" {
                guard let windowID = browserWindowID, let extensionID = bridgeIDs[app.id] else { throw OpenlyError("请重新读取浏览器窗口") }
                var payload: [String: Any] = ["action": "open", "windowId": windowID, "urls": items.map(\.absoluteString)]
                if let groupID { payload["groupId"] = groupID }
                _ = try await BrowserBridge.request(app: app, profile: profile, extensionID: extensionID, payload: payload)
            } else if chromium && mode != "window" {
                try BrowserService.launch(app: app, profile: profile, mode: mode, urls: items)
            } else {
                if mode == "new" && !vscode { try await WindowAccess.createWindow(appID: app.id) }
                if mode == "window" {
                    guard let window = windows.first(where: { $0.id == windowID }) else { throw OpenlyError("请重新选择窗口") }
                    try await WindowAccess.focus(window)
                }
                if vscode {
                    let code = URL(fileURLWithPath: app.path).appendingPathComponent("Contents/Resources/app/bin/code")
                    let arguments = [mode == "new" ? "--new-window" : "--reuse-window", "--"] + items.map { $0.isFileURL ? $0.path : $0.absoluteString }
                    try await ProcessRunner.run(code, arguments: arguments)
                } else {
                    let config = NSWorkspace.OpenConfiguration(); config.activates = true
                    _ = try await NSWorkspace.shared.open(items, withApplicationAt: URL(fileURLWithPath: app.path), configuration: config)
                }
            }
            status = "已交给 \(app.name) 打开"; busy = false; onDismiss?()
        } catch { self.error = error.localizedDescription; onFailure?() }
    }
}

enum ProcessRunner {
    static func run(_ executable: URL, arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process(); process.executableURL = executable; process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            process.terminationHandler = { p in
                if p.terminationStatus == 0 { continuation.resume() }
                else { continuation.resume(throwing: OpenlyError("打开命令失败，退出码 \(p.terminationStatus)")) }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}
