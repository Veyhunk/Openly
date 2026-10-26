import Foundation
import UniformTypeIdentifiers

/// 文件扩展名与默认 App 的关联记录
struct FileAssociation: Identifiable, Hashable {
    let id: String  // UTI identifier 或 扩展名（作为唯一标识）
    let utiIdentifier: String?
    let extensions: [String]        // 该 UTI 对应的扩展名列表（如 public.jpeg → ["jpg", "jpeg"]）
    let defaultAppBundleID: String? // 当前默认打开 App 的 Bundle ID
    let defaultAppName: String?     // 当前默认打开 App 的显示名称
    let defaultAppPath: String?     // 当前默认打开 App 的路径
    let isSystemApp: Bool           // 默认 App 是否为系统原生
    let handlerRole: String         // 处理角色: "all", "viewer", "editor"

    var primaryExtension: String {
        extensions.first ?? "unknown"
    }

    static func == (lhs: FileAssociation, rhs: FileAssociation) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// 扩展名信息（含内置描述）
struct ExtensionInfo: Identifiable, Hashable {
    let id: String           // 扩展名（如 "psd"）
    let utiIdentifier: String?
    let description: String? // 内置描述（如 "Adobe Photoshop 图像文件"）
    let category: String?    // 分类（如 "图像", "文档", "音频"）
    let defaultAppBundleID: String?
    let defaultAppName: String?
    let defaultAppPath: String?
    let isSystemApp: Bool
    let allAvailableApps: [AppInfo]  // 能打开此扩展名的所有 App

    static func == (lhs: ExtensionInfo, rhs: ExtensionInfo) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// 已安装 App 信息
struct AppInfo: Identifiable, Hashable, Codable, Sendable {
    let id: String                // Bundle ID
    let name: String              // 显示名称
    let path: String              // App 路径
    let version: String?          // 版本号（CFBundleShortVersionString）
    let isSystemApp: Bool         // 是否为系统原生 App
    let supportedExtensions: [String] // 该 App 声明的扩展名列表
    let iconPath: String?         // App 图标文件路径（icns）
    var supportedSchemes: [String]? = nil

    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
