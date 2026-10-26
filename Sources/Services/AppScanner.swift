import Foundation
import UniformTypeIdentifiers
import AppKit

/// 扫描已安装应用，提取其支持的文件类型
/// 内置缓存机制——首次扫描后缓存结果，后续调用返回缓存
actor AppScanner {

    // MARK: - 扫描目录

    private let scanDirectories: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: "/System/Applications"),
        URL(fileURLWithPath: "/System/Applications/Utilities"),
        // macOS 系统工具分布在 CoreServices，不能只扫描 Applications。
        URL(fileURLWithPath: "/System/Library/CoreServices/Applications"),
        URL(fileURLWithPath: "/System/Library/CoreServices"),
        URL(fileURLWithPath: "/Library/CoreServices"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/CoreServices"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
    ]

    // MARK: - 缓存

    private var cachedApps: [AppInfo]?
    private var lastScanTime: Date?

    /// 缓存有效期（秒）
    private let cacheTTL: TimeInterval = 300 // 5 分钟

    // MARK: - 公开方法

    /// 扫描所有已安装 App（自动使用缓存）
    func scanAllApps(forceRefresh: Bool = false) async -> [AppInfo] {
        if !forceRefresh, let cached = cachedApps, let lastScan = lastScanTime {
            if Date().timeIntervalSince(lastScan) < cacheTTL {
                return cached
            }
        }

        var allApps: [AppInfo] = []
        for directory in scanDirectories {
            guard FileManager.default.fileExists(atPath: directory.path) else { continue }
            let appURLs = enumerateApps(in: directory)
            for appURL in appURLs {
                if let appInfo = parseApp(at: appURL) {
                    allApps.append(appInfo)
                }
            }
        }

        var unique: [String: AppInfo] = [:]
        for app in allApps where unique[app.id] == nil { unique[app.id] = app }
        let sorted = Array(unique.values).sorted { a, b in
            if a.isSystemApp != b.isSystemApp { return a.isSystemApp }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }

        self.cachedApps = sorted
        self.lastScanTime = Date()
        return sorted
    }

    /// 清除缓存（下次扫描将重新读取磁盘）
    func invalidateCache() {
        cachedApps = nil
        lastScanTime = nil
    }

    /// 获取能打开指定扩展名的所有 App
    func appsForExtension(_ ext: String) async -> [AppInfo] {
        let cleanExt = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let all = await scanAllApps()
        return all.filter { $0.supportedExtensions.contains(cleanExt) }
    }

    /// 获取指定 App 的信息
    func appInfo(for bundleID: String) async -> AppInfo? {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return parseApp(at: appURL)
        }
        let all = await scanAllApps()
        return all.first { $0.id == bundleID }
    }

    // MARK: - 私有方法

    private func enumerateApps(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var appURLs: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "app" else { continue }
            appURLs.append(url)
            enumerator.skipDescendants()
        }
        return appURLs
    }

    private func parseApp(at url: URL) -> AppInfo? {
        let infoPlistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let plist = NSDictionary(contentsOf: infoPlistURL) else { return nil }

        let bundleID = plist["CFBundleIdentifier"] as? String ?? ""
        let name = (plist["CFBundleDisplayName"] as? String) ?? url.deletingPathExtension().lastPathComponent

        let version = plist["CFBundleShortVersionString"] as? String
            ?? plist["CFBundleVersion"] as? String

        let isSystem = bundleID.hasPrefix("com.apple.")
            || url.path.hasPrefix("/System/")

        let extensions = parseDocumentTypes(from: plist)

        guard !bundleID.isEmpty else { return nil }

        let iconName = plist["CFBundleIconFile"] as? String
        let iconPath: String? = if let icon = iconName {
            url.appendingPathComponent("Contents/Resources/\(icon)").path
        } else { nil }

        return AppInfo(
            id: bundleID,
            name: name,
            path: url.path,
            version: version,
            isSystemApp: isSystem,
            supportedExtensions: extensions,
            iconPath: iconPath,
            supportedSchemes: (plist["CFBundleURLTypes"] as? [[String: Any]] ?? []).flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        )
    }

    private func parseDocumentTypes(from plist: NSDictionary) -> [String] {
        var allExtensions = Set<String>()

        guard let docTypes = plist["CFBundleDocumentTypes"] as? [[String: Any]] else {
            return []
        }

        for docType in docTypes {
            if let exts = docType["CFBundleTypeExtensions"] as? [String] {
                allExtensions.formUnion(exts.map { RoutingRules.normalize($0) }.filter { RoutingRules.typeID($0) != nil })
            }
            if let utiStrings = docType["LSItemContentTypes"] as? [String] {
                for utiString in utiStrings {
                    if let utType = UTType(utiString),
                       let tags = utType.tags[.filenameExtension] {
                        allExtensions.formUnion(tags.map { $0.lowercased() })
                    }
                }
            }
            if let mimeTypes = docType["CFBundleTypeMIMETypes"] as? [String] {
                for mime in mimeTypes {
                    if let utType = UTType(mimeType: mime),
                       let tags = utType.tags[.filenameExtension] {
                        allExtensions.formUnion(tags.map { $0.lowercased() })
                    }
                }
            }
        }

        return Array(allExtensions).sorted()
    }
}
