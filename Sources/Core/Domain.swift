import Foundation
import UniformTypeIdentifiers

struct OpenlyError: LocalizedError, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct FileTypeRow: Identifiable, Sendable {
    let id: String
    let typeID: String
    let description: String
    let category: String
    var appID: String?
    var appName: String
    var isSystem: Bool
    var isCommon: Bool { ExtensionUsage.isCommon(id) }
}

struct AssociationRecord: Codable, Identifiable, Sendable {
    var id: String // UTI or scheme:http
    var extensions: [String]
    var previousAppID: String?
    var targetAppID: String
    var createdAt = Date()
    var previousAppSortKey: String { previousAppID ?? "" }
    var statusSortKey: String { targetAppID }
    var commonSortKey: String { extensions.contains(where: ExtensionUsage.isCommon) ? "1" : "0" }
}

enum ExtensionUsage {
    static let common: Set<String> = [
        "txt", "md", "rtf", "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "csv",
        "jpg", "jpeg", "png", "gif", "webp", "heic", "svg", "mp3", "wav", "m4a", "mp4", "mov", "mkv",
        "zip", "7z", "rar", "tar", "gz", "json", "xml", "yaml", "yml", "html", "htm", "css", "js",
        "ts", "tsx", "jsx", "py", "java", "c", "h", "cpp", "swift", "rs"
    ]
    static func isCommon(_ ext: String) -> Bool { common.contains(RoutingRules.normalize(ext)) }
}

struct OperationResult: Identifiable, Sendable {
    let id: String
    let label: String
    var status: Status
    var detail: String
    enum Status: String, Sendable { case success = "已生效", failure = "失败", pending = "待验证", skipped = "无需更改", stopped = "未执行" }
}

struct PlannedChange: Identifiable, Sendable {
    let id: String
    var extensions: [String]
    var previousAppID: String?
    var targetAppID: String
    var issue: String?
    var label: String { id.hasPrefix("scheme:") ? String(id.dropFirst(7)).uppercased() : extensions.map { "." + $0 }.joined(separator: ", ") }
}

struct BackupConfig: Codable, Sendable {
    var version = "2.0"
    var exportDate = ISO8601DateFormatter().string(from: Date())
    var associations: [Entry]
    struct Entry: Codable, Sendable {
        var uti: String?
        var extensions: [String]
        var bundleID: String
        var appName: String?
        var takeover: Bool?
        var scheme: String?
    }
}

enum RoutingRules {
    static let receiverID = "com.openly.receiver"
    static let batchReceiverID = "com.openly.receiver.batch"
    static let managerID = "com.openly.app"
    static func isReceiverID(_ id: String?) -> Bool { id == receiverID || id == batchReceiverID }
    static func normalize(_ ext: String) -> String { ext.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased() }
    static func typeID(_ ext: String) -> String? {
        let ext = normalize(ext)
        guard !ext.isEmpty, ext != "*", !ext.contains("/"), !ext.contains(" ") else { return nil }
        return UTType(filenameExtension: ext)?.identifier
    }
    static func plan(_ extensions: [String], target: String, current: (String) -> String?) -> [PlannedChange] {
        var groups: [String: Set<String>] = [:]
        for value in extensions {
            let ext = normalize(value)
            let key = typeID(ext) ?? "unknown:\(ext)"
            groups[key, default: []].insert(ext)
            if let type = UTType(key) { groups[key, default: []].formUnion(type.tags[.filenameExtension] ?? []) }
        }
        return groups.keys.sorted().map { key in
            PlannedChange(id: key, extensions: groups[key]!.sorted(), previousAppID: current(key), targetAppID: target,
                          issue: key.hasPrefix("unknown:") ? "无法解析文件类型" : nil)
        }
    }
    static func validate(_ config: BackupConfig) throws {
        guard ["1.0", "2.0"].contains(config.version) else { throw OpenlyError("不支持配置版本 \(config.version)") }
        guard config.associations.count <= 10000 else { throw OpenlyError("配置条目过多") }
    }
    static func recoveryTarget(record: AssociationRecord, current: String?) -> String? {
        current == record.targetAppID ? record.previousAppID : current
    }
}

struct LocalState: Codable, Sendable {
    var version = 1
    var records: [AssociationRecord] = []
    var apps: [AppInfo] = []
    var bridgeIDs: [String: String] = [:]
}

enum StateFiles {
    static var root: URL {
        if let path = ProcessInfo.processInfo.environment["OPENLY_STATE_DIR"] { return URL(fileURLWithPath: path) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Openly")
    }
    static var stateURL: URL { root.appendingPathComponent("state.json") }
    static func read() throws -> LocalState {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return LocalState() }
        return try JSONDecoder().decode(LocalState.self, from: Data(contentsOf: stateURL))
    }
    static func write(_ state: LocalState) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
    }
}
