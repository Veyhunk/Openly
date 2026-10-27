import Foundation
import AppKit

struct BrowserProfile: Identifiable, Sendable {
    let id: String
    let name: String
    let account: String?
    init(id: String, name: String, account: String? = nil) {
        self.id = id; self.name = name; self.account = account
    }
    var label: String { account.map { "\(name) · \($0)" } ?? name }
}
struct BrowserWindow: Codable, Identifiable, Sendable {
    let id: Int
    let title: String
    let incognito: Bool
    let count: Int
}
struct BrowserGroup: Codable, Identifiable, Sendable {
    let id: Int
    let windowId: Int
    let title: String
    let color: String
}
struct BrowserSnapshot: Codable, Sendable {
    var windows: [BrowserWindow]
    var groups: [BrowserGroup]
}

enum BrowserService {
    static func isChromium(_ id: String) -> Bool { ["com.google.Chrome", "com.microsoft.edgemac", "org.chromium.Chromium", "com.google.Chrome.forTesting"].contains(id) }
    static func dataRoot(_ id: String) -> URL {
        let sub = id == "com.microsoft.edgemac" ? "Microsoft Edge" : id == "org.chromium.Chromium" ? "Chromium" : id == "com.google.Chrome.forTesting" ? "Google/Chrome for Testing" : "Google/Chrome"
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/" + sub)
    }
    static func profiles(_ id: String) -> [BrowserProfile] {
        let url = dataRoot(id).appendingPathComponent("Local State")
        guard let data = try? Data(contentsOf: url), let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let profile = json["profile"] as? [String: Any], let cache = profile["info_cache"] as? [String: [String: Any]] else { return [.init(id: "Default", name: "默认个人资料", account: nil)] }
        return cache.keys.sorted().filter { !$0.contains("/") && !$0.contains("..") }.map {
            let info = cache[$0] ?? [:]
            let name = info["name"] as? String ?? $0
            let account = (info["user_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (info["gaia_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return .init(id: $0, name: name, account: account)
        }
    }
    static func arguments(profile: String, mode: String, urls: [URL], temporaryDirectory: URL? = nil) -> [String] {
        var args: [String] = []
        if let temporaryDirectory { args += ["--user-data-dir=" + temporaryDirectory.path] }
        else { args += ["--profile-directory=" + profile] }
        if mode == "new" || mode == "temporary" { args.append("--new-window") }
        if mode == "incognito" { args.append("--incognito") }
        return args + urls.map(\.absoluteString)
    }
    static func launch(app: AppInfo, profile: String, mode: String, urls: [URL]) throws {
        guard let executable = Bundle(path: app.path)?.executableURL else { throw OpenlyError("找不到浏览器可执行文件") }
        var temporary: URL?
        if mode == "temporary" {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Openly-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]); temporary = url
        }
        let args = arguments(profile: profile, mode: mode, urls: urls, temporaryDirectory: temporary)
        let process = Process()
        if temporary == nil {
            // Chromium 会把直接启动请求转给已运行的主进程，导致 --profile-directory 被忽略。
            // `open -n --args` 强制创建一个实例，让指定 Profile 真正参与启动。
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-n", app.path, "--args"] + args
        } else {
            process.executableURL = executable
            process.arguments = args
        }
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
    }
}

@MainActor enum BrowserBridge {
    static func validExtensionID(_ id: String) -> Bool { id.count == 32 && id.allSatisfy { ("a"..."p").contains(String($0)) } }
    static func hostManifestURL(_ appID: String) -> URL {
        BrowserService.dataRoot(appID).appendingPathComponent("NativeMessagingHosts/com.openly.bridge.json")
    }
    static func hostConfigured(appID: String, extensionID: String?) -> Bool {
        guard let extensionID, validExtensionID(extensionID), FileManager.default.fileExists(atPath: hostManifestURL(appID).path),
              let data = try? Data(contentsOf: hostManifestURL(appID)), let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let origins = manifest["allowed_origins"] as? [String] else { return false }
        return origins.contains("chrome-extension://\(extensionID)/") && FileManager.default.isExecutableFile(atPath: (manifest["path"] as? String) ?? "")
    }
    static func connectionHint(appID: String, extensionID: String?) -> String {
        guard let extensionID, validExtensionID(extensionID) else { return "未配置扩展 ID" }
        guard FileManager.default.fileExists(atPath: hostManifestURL(appID).path) else { return "未注册 Native Messaging 主机" }
        guard hostConfigured(appID: appID, extensionID: extensionID) else { return "主机路径或扩展 ID 不匹配" }
        return "已注册，读取窗口时会按 Profile 连接"
    }
    static func install(appID: String, extensionID: String) throws {
        guard validExtensionID(extensionID) else { throw OpenlyError("扩展 ID 格式不正确") }
        let host = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/OpenlyBridge")
        guard FileManager.default.isExecutableFile(atPath: host.path) else { throw OpenlyError("请使用完整 Openly.app 配置扩展") }
        let folder = BrowserService.dataRoot(appID).appendingPathComponent("NativeMessagingHosts")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest: [String: Any] = ["name": "com.openly.bridge", "description": "Openly browser routing", "path": host.path, "type": "stdio", "allowed_origins": ["chrome-extension://\(extensionID)/"]]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted]).write(to: folder.appendingPathComponent("com.openly.bridge.json"), options: .atomic)
    }
    static func request(app: AppInfo, profile: String, extensionID: String, payload: [String: Any]) async throws -> Data {
        guard validExtensionID(extensionID) else { throw OpenlyError("请在打开接管页连接浏览器扩展") }
        let folder = StateFiles.root.appendingPathComponent("bridge")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let token = UUID().uuidString
        let request = folder.appendingPathComponent(token + ".json"), result = folder.appendingPathComponent(token + ".result.json")
        var body = payload; body["expires"] = Date().timeIntervalSince1970 + 30
        try JSONSerialization.data(withJSONObject: body).write(to: request, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: request.path)
        defer { try? FileManager.default.removeItem(at: request); try? FileManager.default.removeItem(at: result); try? FileManager.default.removeItem(at: folder.appendingPathComponent(token + ".claimed.json")) }
        let url = URL(string: "chrome-extension://\(extensionID)/bridge.html#\(token)")!
        try BrowserService.launch(app: app, profile: profile, mode: "default", urls: [url])
        // 仅在主动请求期间等待，空闲时没有轮询或长连接。
        for _ in 0..<100 {
            try Task.checkCancellation()
            if let data = try? Data(contentsOf: result) {
                if let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let error = json["error"] as? String { throw OpenlyError(error) }
                return data
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw OpenlyError("扩展未响应。请确认当前个人资料已安装扩展，并在接管页配置正确 ID。")
    }
}
