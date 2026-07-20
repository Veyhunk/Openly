import Foundation
import UniformTypeIdentifiers
import AppKit

/// 写入/修改 macOS Launch Services 文件关联
/// 使用 macOS 12+ 现代 API: NSWorkspace.setDefaultApplication(at:toOpenContentType:)
actor LaunchServicesWriter {

    // MARK: - 错误类型

    enum WriteError: Error, LocalizedError {
        case unknownExtension(String)
        case appNotFound(String)
        case setFailed(String)
        case systemProtected(String)

        var errorDescription: String? {
            switch self {
            case .unknownExtension(let ext): "无法识别扩展名: .\(ext)"
            case .appNotFound(let id): "未找到应用: \(id)"
            case .setFailed(let msg): "设置失败: \(msg)"
            case .systemProtected(let msg): "系统保护: \(msg)"
            }
        }
    }

    // MARK: - 公开方法

    /// 为指定扩展名设置默认打开 App
    /// - Parameters:
    ///   - ext: 文件扩展名（如 "pdf", "txt"）
    ///   - bundleID: 目标 App 的 Bundle ID
    func setDefaultApp(forExtension ext: String, bundleID: String) async throws {
        let cleanExt = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))

        // 1. 扩展名 → UTType
        guard let utType = UTType(tag: cleanExt, tagClass: .filenameExtension, conformingTo: nil) else {
            throw WriteError.unknownExtension(cleanExt)
        }

        // 2. Bundle ID → App URL
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw WriteError.appNotFound(bundleID)
        }

        // 3. 调用 API 设置默认 App
        try await NSWorkspace.shared.setDefaultApplication(
            at: appURL,
            toOpen: utType
        )
    }

    /// 批量设置默认 App
    /// - Parameters:
    ///   - extensions: 文件扩展名列表
    ///   - bundleID: 目标 App Bundle ID
    /// - Returns: 每个扩展名的操作结果
    func setDefaultAppBatch(extensions: [String], bundleID: String) async -> [(ext: String, success: Bool, error: String?)] {
        var results: [(ext: String, success: Bool, error: String?)] = []

        for ext in extensions {
            do {
                try await setDefaultApp(forExtension: ext, bundleID: bundleID)
                results.append((ext, true, nil))
            } catch {
                results.append((ext, false, error.localizedDescription))
            }
        }

        return results
    }

    /// 清除某扩展名的默认 App 关联
    /// 通过写入 LSHandlers 将关联移除（恢复为系统默认行为）
    func clearAssociation(forExtension ext: String) async throws {
        let cleanExt = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))

        guard let utType = UTType(tag: cleanExt, tagClass: .filenameExtension, conformingTo: nil) else {
            throw WriteError.unknownExtension(cleanExt)
        }

        // 从 LSHandlers 中移除该 UTI 的条目
        let plistURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist")

        guard FileManager.default.fileExists(atPath: plistURL.path),
              let plist = NSMutableDictionary(contentsOf: plistURL),
              var handlers = plist["LSHandlers"] as? [[String: Any]] else {
            throw WriteError.setFailed("无法读取 LSHandlers")
        }

        // 过滤掉目标 UTI
        let utiID = utType.identifier
        handlers.removeAll { handler in
            handler["LSHandlerContentType"] as? String == utiID
        }

        plist["LSHandlers"] = handlers
        try plist.write(to: plistURL)
    }

    /// 检查 App 是否存在
    func appExists(bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }
}
