import Foundation
import AppKit

struct BrowserProfile: Identifiable, Sendable { let id: String; let name: String }
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
              let profile = json["profile"] as? [String: Any], let cache = profile["info_cache"] as? [String: [String: Any]] else { return [.init(id: "Default", name: "默认个人资料")] }
        return cache.keys.sorted().filter { !$0.contains("/") && !$0.contains("..") }.map { .init(id: $0, name: cache[$0]?["name"] as? String ?? $0) }
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
        let process = Process(); process.executableURL = executable
        process.arguments = arguments(profile: profile, mode: mode, urls: urls, temporaryDirectory: temporary)
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
    }
}

@MainActor enum BrowserBridge {
    static func validExtensionID(_ id: String) -> Bool { id.count == 32 && id.allSatisfy { ("a"..."p").contains(String($0)) } }
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
