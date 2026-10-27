import AppKit
import UniformTypeIdentifiers
import CoreServices

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
        if id == RoutingRules.batchReceiverID {
            let batch = StateFiles.root.appendingPathComponent("Receiver.app")
            if FileManager.default.fileExists(atPath: batch.path) { return batch }
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
    static func prepareBatchReceiver(for changes: [PlannedChange]) throws {
        let source = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Openly Receiver.app")
        guard FileManager.default.fileExists(atPath: source.path) else { throw OpenlyError("未找到接收器模板，请先使用完整 Openly.app") }
        let fm = FileManager.default
        let root = StateFiles.root
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let destination = root.appendingPathComponent("Receiver.app")
        let temporary = root.appendingPathComponent(".Receiver-\(UUID().uuidString).app")
        try? fm.removeItem(at: temporary)
        try fm.copyItem(at: source, to: temporary)
        let infoURL = temporary.appendingPathComponent("Contents/Info.plist")
        guard var info = NSDictionary(contentsOf: infoURL) as? [String: Any] else { throw OpenlyError("接收器模板信息无效") }
        var allChanges = changes
        if let state = try? StateFiles.read() {
            for record in state.records where record.targetAppID == RoutingRules.batchReceiverID && !allChanges.contains(where: { $0.id == record.id }) {
                allChanges.append(.init(id: record.id, extensions: record.extensions, previousAppID: record.previousAppID, targetAppID: record.targetAppID))
            }
        }
        let types = allChanges.filter { !$0.id.hasPrefix("scheme:") }.map { change -> [String: Any] in
            ["CFBundleTypeName": change.label, "CFBundleTypeRole": "Viewer", "LSHandlerRank": "Owner", "LSItemContentTypes": [change.id], "CFBundleTypeExtensions": change.extensions]
        }
        info["CFBundleIdentifier"] = RoutingRules.batchReceiverID
        info["CFBundleDisplayName"] = "Openly 批量接收器"
        info["CFBundleDocumentTypes"] = types
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: infoURL, options: .atomic)
        try? fm.removeItem(at: destination)
        try fm.moveItem(at: temporary, to: destination)
        let sign = Process(); sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign"); sign.arguments = ["--force", "--deep", "--sign", "-", destination.path]; try sign.run(); sign.waitUntilExit()
        guard sign.terminationStatus == 0 else { throw OpenlyError("批量接收器签名失败") }
        guard LSRegisterURL(destination as CFURL, true) == noErr else { throw OpenlyError("批量接收器注册失败") }
    }
    static func name(_ id: String?) -> String {
        guard let id else { return "未找到默认应用" }
        if RoutingRules.isReceiverID(id) { return "Openly · 每次选择" }
        guard let url = appURL(id) else { return id + "（未安装）" }
        return url.deletingPathExtension().lastPathComponent
    }
}
