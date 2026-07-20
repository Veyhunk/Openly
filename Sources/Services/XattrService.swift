import Foundation

/// 管理文件的 extended attributes（com.apple.LaunchServices.OpenWith 覆盖）
actor XattrService {

    // xattr 键名
    private let openWithKey = "com.apple.LaunchServices.OpenWith"

    // MARK: - 检测

    /// 检查指定路径是否有单文件 OpenWith 覆盖
    func hasOverride(at path: String) -> Bool {
        let data = getxattr(path, openWithKey, nil, 0, 0, 0)
        return data > 0
    }

    /// 批量检查哪些扩展名对应的文件有 xattr 覆盖
    /// 注：扩展名级别的 xattr 检查需要示例文件，此处检查用户 home 目录常见位置
    func findOverrides(extensions: [String]) async -> [(ext: String, paths: [String])] {
        var results: [(ext: String, paths: [String])] = []

        for ext in extensions {
            let searchPaths = commonFilePaths(for: ext)
            var foundPaths: [String] = []

            for path in searchPaths {
                if FileManager.default.fileExists(atPath: path) && hasOverride(at: path) {
                    foundPaths.append(path)
                }
            }

            if !foundPaths.isEmpty {
                results.append((ext, foundPaths))
            }
        }

        return results
    }

    // MARK: - 清除

    /// 清除单文件的 OpenWith xattr
    func clearOverride(at path: String) -> Bool {
        let result = removexattr(path, openWithKey, 0)
        return result == 0
    }

    /// 批量清除指定路径的 xattr
    func clearOverrides(at paths: [String]) -> (success: Int, failed: Int) {
        var success = 0, failed = 0
        for path in paths {
            if clearOverride(at: path) { success += 1 }
            else { failed += 1 }
        }
        return (success, failed)
    }

    // MARK: - 辅助

    /// 推测某个扩展名在用户系统中的常见文件路径
    private func commonFilePaths(for ext: String) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cleanExt = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))

        return [
            home.appendingPathComponent("Desktop").path,
            home.appendingPathComponent("Downloads").path,
            home.appendingPathComponent("Documents").path
        ].flatMap { dir -> [String] in
            guard FileManager.default.fileExists(atPath: dir) else { return [] }
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
            let matches = contents
                .filter { $0.lowercased().hasSuffix(".\(cleanExt)") }
                .map { "\(dir)/\($0)" }
            return Array(matches.prefix(3))
        }
    }
}
