import SwiftUI
import Observation
import AppKit
import UniformTypeIdentifiers

@MainActor @Observable
final class RouterModel {
    var urls: [URL] = []
    var queue: [[URL]] = []
    var apps: [AppInfo] = []
    var selectedAppID: String?
    var search = ""
    var step = "apps"
    var onlyCompatible = true
    var optionSearch = ""
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
    var browserSnapshots: [String: BrowserSnapshot] = [:]
    var targetErrors: [String: String] = [:]
    var busy = false
    var loadingTargets = false
    var error: String?
    var status = ""
    var allowUnsupported = false
    var onDismiss: (() -> Void)?
    var onWillOpen: (() -> Void)?
    var onFailure: (() -> Void)?
    var bridgeIDs: [String: String] = [:]
    var localState = LocalState()
    private var targetTask: Task<Void, Never>?
    private var generation = 0
    var selectedApp: AppInfo? { apps.first { $0.id == selectedAppID } }
    var systemDefaultApp: AppInfo? {
        guard let url = urls.first else { return nil }
        let key: String?
        if url.isFileURL, let type = UTType(filenameExtension: url.pathExtension) { key = type.identifier }
        else if let scheme = url.scheme { key = "scheme:\(scheme.lowercased())" }
        else { key = nil }
        guard let key else { return nil }
        let current = AssociationService.current(key)
        let fallback = localState.records.first { $0.id == key && RoutingRules.isReceiverID(current) }?.previousAppID
        return apps.first { $0.id == (fallback ?? current) }
    }
    func isOriginalDefault(_ option: RouteOption) -> Bool {
        guard option.mode == "default", let app = selectedApp, systemDefaultApp?.id == app.id else { return false }
        return !chromium || option.profile == profiles.first?.id
    }
    var chromium: Bool { selectedAppID.map(BrowserService.isChromium) == true }
    var vscode: Bool { selectedAppID == "com.microsoft.VSCode" || selectedAppID == "com.microsoft.VSCodeInsiders" }
    var candidates: [AppInfo] { apps.filter { (!onlyCompatible || supports($0)) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }.sorted { a,b in
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
        do { localState = try StateFiles.read(); apps = localState.apps; bridgeIDs = localState.bridgeIDs; updateCompatibility() }
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
    func openUsingSystemDefault() async {
        guard let app = systemDefaultApp, !busy, let appURL = AssociationService.appURL(app.id) else { return }
        busy = true; error = nil; onWillOpen?()
        defer { busy = false }
        do {
            let config = NSWorkspace.OpenConfiguration(); config.activates = true
            _ = try await NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: config)
            status = "已按默认方式交给 \(app.name) 打开"; onDismiss?()
        } catch let openError { self.error = openError.localizedDescription; onFailure?() }
    }
    func resetTarget() {
        targetTask?.cancel(); generation += 1; selectedAppID = nil; mode = "default"; profile = "Default"
        windows = []; browserSnapshots = [:]; targetErrors = [:]; error = nil; search = ""; optionSearch = ""; step = "apps"; onlyCompatible = true; allowUnsupported = false
    }
    func appChanged() {
        targetTask?.cancel(); generation += 1; loadingTargets = false
        mode = "default"; windowID = nil; browserWindowID = nil; groupID = nil
        browserSnapshots = [:]; targetErrors = [:]; allowUnsupported = false
        profiles = chromium ? (selectedAppID.map(BrowserService.profiles) ?? []) : []
        profile = profiles.first?.id ?? "Default"
        refreshWindows()
    }
    func refreshWindows() { windows = selectedAppID.map(WindowAccess.windows) ?? []; windowID = nil; genericNewWindow = !chromium && !vscode && selectedAppID.flatMap { WindowAccess.newWindowAction(appID: $0) } != nil }
    func selectApp(_ id: String) {
        selectedAppID = id; appChanged(); optionSearch = ""; step = "options"
        if chromium, bridgeIDs[id] != nil { loadBrowserTargets() }
        let options = availableOptions
        if OpenlyPreferences.autoOpenSingleOption, options.count == 1, let only = options.first {
            Task { await choose(only) }
        }
    }
    func backToApps() {
        targetTask?.cancel(); generation += 1; loadingTargets = false; step = "apps"; error = nil
    }
    func loadBrowserTargets() {
        guard let app = selectedApp, let extID = bridgeIDs[app.id] else { error = "请先在打开接管页连接扩展"; return }
        targetTask?.cancel(); generation += 1; let version = generation; let profiles = profiles
        loadingTargets = true; error = nil; targetErrors = [:]
        targetTask = Task {
            for p in profiles {
                guard generation == version, !Task.isCancelled else { return }
                do {
                    let data = try await BrowserBridge.request(app: app, profile: p.id, extensionID: extID, payload: ["action": "list"])
                    let value = try JSONDecoder().decode(BrowserSnapshot.self, from: data)
                    guard generation == version else { return }
                    browserSnapshots[p.id] = value
                } catch {
                    guard generation == version else { return }
                    targetErrors[p.name] = error.localizedDescription
                }
                if !busy { onFailure?() }
            }
            if generation == version { loadingTargets = false }
        }
    }
    var canOpen: Bool {
        guard let app = selectedApp, !busy, supports(app) || allowUnsupported else { return false }
        if mode == "window" { return windowID != nil }
        if mode == "browserWindow" { return browserWindowID != nil }
        return true
    }
    func openSelected() async {
        guard let app = selectedApp, canOpen else { return }
        targetTask?.cancel(); generation += 1; loadingTargets = false
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
