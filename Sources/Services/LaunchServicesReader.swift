import Foundation
import UniformTypeIdentifiers
import AppKit

/// 读取 macOS Launch Services 文件关联数据库
/// 数据来源：~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist
actor LaunchServicesReader {

    // MARK: - 错误类型

    enum ReadError: Error, LocalizedError {
        case plistNotFound
        case invalidFormat
        case noHandlers

        var errorDescription: String? {
            switch self {
            case .plistNotFound: "未找到 Launch Services 配置文件"
            case .invalidFormat: "Launch Services 数据格式异常"
            case .noHandlers: "未找到任何文件关联记录"
            }
        }
    }

    // MARK: - 存储路径

    private var securePlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist")
    }

    // MARK: - 公开方法

    /// 读取所有文件扩展名关联（LSHandlers）
    func readAllAssociations() throws -> [FileAssociation] {
        guard FileManager.default.fileExists(atPath: securePlistURL.path) else {
            throw ReadError.plistNotFound
        }

        guard let plist = NSDictionary(contentsOf: securePlistURL),
              let handlers = plist["LSHandlers"] as? [[String: Any]] else {
            throw ReadError.invalidFormat
        }

        guard !handlers.isEmpty else {
            throw ReadError.noHandlers
        }

        // 按 UTI 聚合关联
        var associationMap: [String: FileAssociation] = [:]

        for handler in handlers {
            // 只处理文件类型（非 URL Scheme）
            guard let contentType = handler["LSHandlerContentType"] as? String else {
                continue
            }

            let bundleID = handler["LSHandlerRoleAll"] as? String
                ?? handler["LSHandlerRoleViewer"] as? String
                ?? handler["LSHandlerRoleEditor"] as? String

            let role: String = {
                if handler["LSHandlerRoleAll"] != nil { return "all" }
                if handler["LSHandlerRoleViewer"] != nil { return "viewer" }
                if handler["LSHandlerRoleEditor"] != nil { return "editor" }
                return "all"
            }()

            // 从 UTI 获取扩展名列表
            let extensions = self.extensions(forUTI: contentType)

            // 如果同一 UTI 有多条记录，以第一条为准
            guard associationMap[contentType] == nil else { continue }

            let appName = bundleID.flatMap { self.appName(for: $0) }
            let appPath = bundleID.flatMap { self.appPath(for: $0) }
            let isSystem = bundleID.map { $0.hasPrefix("com.apple.") } ?? false

            associationMap[contentType] = FileAssociation(
                id: contentType,
                utiIdentifier: contentType,
                extensions: extensions,
                defaultAppBundleID: bundleID,
                defaultAppName: appName,
                defaultAppPath: appPath,
                isSystemApp: isSystem,
                handlerRole: role
            )
        }

        return Array(associationMap.values)
            .filter { !$0.extensions.isEmpty }
            .sorted { $0.primaryExtension < $1.primaryExtension }
    }

    /// 获取指定扩展名的默认关联
    func getAssociation(forExtension ext: String) throws -> FileAssociation? {
        let all = try readAllAssociations()
        return all.first { $0.extensions.contains(ext.lowercased()) }
    }

    /// 获取指定 App 关联的所有扩展名
    func getAssociations(forApp bundleID: String) throws -> [FileAssociation] {
        let all = try readAllAssociations()
        return all.filter { $0.defaultAppBundleID == bundleID }
    }

    // MARK: - 私有方法

    /// UTI → 扩展名列表
    private func extensions(forUTI utiString: String) -> [String] {
        guard let utType = UTType(utiString) else { return [] }
        return utType.tags[.filenameExtension] ?? []
    }

    /// Bundle ID → App 名称
    private func appName(for bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    /// Bundle ID → App 路径
    private func appPath(for bundleID: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path
    }
}
