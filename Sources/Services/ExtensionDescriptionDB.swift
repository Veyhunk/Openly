import Foundation

/// 内置扩展名描述数据库
/// 数据来源：Sources/Resources/extension_descriptions.json
actor ExtensionDescriptionDB {

    // MARK: - 数据结构

    private struct DescriptionData: Codable {
        let categories: [String: [String]]
        let descriptions: [String: String]
    }

    // MARK: - 缓存

    private var data: DescriptionData?
    private var categoryReverseIndex: [String: String] = [:] // ext → category

    // MARK: - 加载

    private func ensureLoaded() {
        guard data == nil else { return }

        guard let url = ResourceHelper.url(
            forResource: "extension_descriptions",
            withExtension: "json"
        ) else {
            print("[ExtensionDescriptionDB] 资源文件未找到")
            data = DescriptionData(categories: [:], descriptions: [:])
            return
        }

        do {
            let jsonData = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            data = try decoder.decode(DescriptionData.self, from: jsonData)
            buildReverseIndex()
        } catch {
            print("[ExtensionDescriptionDB] 解析失败: \(error)")
            data = DescriptionData(categories: [:], descriptions: [:])
        }
    }

    private func buildReverseIndex() {
        guard let data else { return }
        categoryReverseIndex.removeAll()
        for (category, extensions) in data.categories {
            for ext in extensions {
                categoryReverseIndex[ext] = category
            }
        }
    }

    // MARK: - 公开方法

    /// 获取扩展名描述
    func description(for ext: String) -> String? {
        ensureLoaded()
        let clean = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return data?.descriptions[clean]
    }

    /// 获取扩展名分类
    func category(for ext: String) -> String? {
        ensureLoaded()
        let clean = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return categoryReverseIndex[clean]
    }

    /// 获取某个分类下的所有扩展名
    func extensions(in category: String) -> [String] {
        ensureLoaded()
        return data?.categories[category] ?? []
    }

    /// 获取所有已知扩展名及其描述（批量，避免多次 actor 调用）
    func allExtensionsInfo() -> [(ext: String, desc: String?, category: String?)] {
        ensureLoaded()
        guard let data else { return [] }
        var result: [(String, String?, String?)] = []
        for (cat, exts) in data.categories {
            for ext in exts {
                result.append((ext, data.descriptions[ext], cat))
            }
        }
        return result
    }

    /// 获取所有分类
    func allCategories() -> [String] {
        ensureLoaded()
        guard let categories = data?.categories else { return [] }
        return Array(categories.keys).sorted()
    }

    /// 批量获取扩展名信息
    func batchInfo(for extensions: [String]) -> [(ext: String, desc: String?, category: String?)] {
        ensureLoaded()
        return extensions.map { ext in
            let clean = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return (ext, data?.descriptions[clean], categoryReverseIndex[clean])
        }
    }

    /// 搜索扩展名描述
    func search(_ query: String) -> [String] {
        ensureLoaded()
        let lowerQuery = query.lowercased()

        var results: Set<String> = []

        // 匹配扩展名
        if data?.descriptions[lowerQuery] != nil {
            results.insert(lowerQuery)
        }

        // 匹配描述内容
        for (ext, desc) in data?.descriptions ?? [:] {
            if desc.lowercased().contains(lowerQuery) {
                results.insert(ext)
            }
        }

        // 匹配分类
        if let exts = data?.categories[lowerQuery] {
            results.formUnion(exts)
        }

        return Array(results).sorted()
    }
}
