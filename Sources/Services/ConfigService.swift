import Foundation

/// 配置文件导入/导出服务
/// 支持 JSON 格式的关联配置备份和恢复
actor ConfigService {

    // MARK: - 数据结构

    struct AssociationConfig: Codable {
        let version: String
        let exportDate: String
        let associations: [AssociationEntry]
    }

    struct AssociationEntry: Codable {
        let uti: String?
        let extensions: [String]
        let bundleID: String
        let appName: String?
    }

    struct ImportResult {
        let total: Int
        let success: Int
        let skipped: Int
        let errors: [String]
    }

    // MARK: - 导出

    /// 导出当前所有文件关联到 JSON
    func exportAssociations(
        from associations: [FileAssociation],
        to url: URL
    ) async throws {
        let entries = associations.map { assoc in
            AssociationEntry(
                uti: assoc.utiIdentifier,
                extensions: assoc.extensions,
                bundleID: assoc.defaultAppBundleID ?? "",
                appName: assoc.defaultAppName
            )
        }

        let dateFormatter = ISO8601DateFormatter()
        let config = AssociationConfig(
            version: "1.0",
            exportDate: dateFormatter.string(from: Date()),
            associations: entries
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: url)
    }

    /// 从 JSON 读取关联配置
    func readConfig(from url: URL) async throws -> AssociationConfig {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(AssociationConfig.self, from: data)
    }

    /// 导入配置中的关联
    func importAssociations(
        from config: AssociationConfig,
        writer: LaunchServicesWriter
    ) async -> ImportResult {
        var success = 0
        var skipped = 0
        var errors: [String] = []

        for entry in config.associations {
            guard !entry.bundleID.isEmpty else { skipped += 1; continue }

            for ext in entry.extensions {
                do {
                    try await writer.setDefaultApp(forExtension: ext, bundleID: entry.bundleID)
                    success += 1
                } catch {
                    errors.append(".\(ext): \(error.localizedDescription)")
                }
            }
        }

        return ImportResult(
            total: config.associations.flatMap { $0.extensions }.count,
            success: success,
            skipped: skipped,
            errors: errors
        )
    }
}
