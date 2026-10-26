import AppKit
import UniformTypeIdentifiers

@MainActor
enum AssociationService {
    static func current(_ id: String) -> String? {
        let url: URL?
        if id.hasPrefix("scheme:") {
            guard let probe = URL(string: String(id.dropFirst(7)) + "://openly.invalid") else { return nil }
            url = NSWorkspace.shared.urlForApplication(toOpen: probe)
        } else {
            guard let type = UTType(id) else { return nil }
            url = NSWorkspace.shared.urlForApplication(toOpen: type)
        }
        return url.flatMap { Bundle(url: $0)?.bundleIdentifier }
    }
    static func appURL(_ id: String) -> URL? {
        if id == RoutingRules.receiverID {
            let embedded = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Openly Receiver.app")
            if FileManager.default.fileExists(atPath: embedded.path) { return embedded }
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    }
    static func write(_ id: String, appID: String) async throws {
        guard let app = appURL(appID) else { throw OpenlyError("未找到应用，请先安装完整 Openly.app 或重新选择目标应用") }
        if id.hasPrefix("scheme:") {
            try await NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: String(id.dropFirst(7)))
        } else {
            guard let type = UTType(id) else { throw OpenlyError("无法解析类型 \(id)") }
            try await NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type)
        }
    }
    static func name(_ id: String?) -> String {
        guard let id else { return "未找到默认应用" }
        if id == RoutingRules.receiverID { return "Openly · 每次选择" }
        guard let url = appURL(id) else { return id + "（未安装）" }
        return url.deletingPathExtension().lastPathComponent
    }
}
