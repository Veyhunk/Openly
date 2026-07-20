import Foundation
import UniformTypeIdentifiers
import AppKit

/// 扫描已安装应用，提取其支持的文件类型
actor AppScanner {

    // MARK: - 扫描目录

    private let scanDirectories: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: "/System/Applications"),
        URL(fileURLWithPath: "/System/Applications/Utilities"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
    ]

    // MARK: - 公开方法

    /// 扫描所有已安装 App 及其支持的文档类型
    func scanAllApps() async -> [AppInfo] {
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

        // 按名称排序，系统 App 优先
        return allApps.sorted { a, b in
            if a.isSystemApp != b.isSystemApp { return a.isSystemApp }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// 获取能打开指定扩展名的所有 App
    func appsForExtension(_ ext: String) async -> [AppInfo] {
        let cleanExt = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let all = await scanAllApps()
        return all.filter { $0.supportedExtensions.contains(cleanExt) }
    }

    /// 获取指定 App 的信息
    func appInfo(for bundleID: String) async -> AppInfo? {
        // 先从已知路径查找
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return parseApp(at: appURL)
        }

        // 回退扫描
        let all = await scanAllApps()
        return all.first { $0.id == bundleID }
    }

    // MARK: - 私有方法

    /// 枚举目录下的 .app
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
            enumerator.skipDescendants() // 不深入 .app 内部
        }
        return appURLs
    }

    /// 解析单个 App 的 Info.plist
    private func parseApp(at url: URL) -> AppInfo? {
        let infoPlistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let plist = NSDictionary(contentsOf: infoPlistURL) else { return nil }

        let bundleID = plist["CFBundleIdentifier"] as? String ?? ""
        let name = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent

        let isSystem = bundleID.hasPrefix("com.apple.")
            || url.path.hasPrefix("/System/")

        let extensions = parseDocumentTypes(from: plist)

        guard !extensions.isEmpty else { return nil }

        return AppInfo(
            id: bundleID,
            name: name,
            path: url.path,
            isSystemApp: isSystem,
            supportedExtensions: extensions,
            iconName: nil
        )
    }

    /// 从 Info.plist 提取 CFBundleDocumentTypes 中的扩展名
    private func parseDocumentTypes(from plist: NSDictionary) -> [String] {
        var allExtensions = Set<String>()

        guard let docTypes = plist["CFBundleDocumentTypes"] as? [[String: Any]] else {
            return []
        }

        for docType in docTypes {
            // 直接声明的扩展名
            if let exts = docType["CFBundleTypeExtensions"] as? [String] {
                allExtensions.formUnion(exts.map { $0.lowercased() })
            }

            // 从 UTI 解析扩展名
            if let utiStrings = docType["LSItemContentTypes"] as? [String] {
                for utiString in utiStrings {
                    if let utType = UTType(utiString),
                       let tags = utType.tags[.filenameExtension] {
                        allExtensions.formUnion(tags.map { $0.lowercased() })
                    }
                }
            }

            // 从 MIME 类型反查扩展名
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
