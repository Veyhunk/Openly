import Foundation

/// 资源文件定位 — 兼容 .app bundle 和 SPM 开发两种运行模式
enum ResourceHelper {

    static func url(forResource name: String, withExtension ext: String) -> URL? {
        // 1) main bundle（.app 运行模式）
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }

        // 2) 相对于可执行文件搜索（SPM 开发模式 / CI）
        if let execDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            let candidates: [URL] = [
                execDir.appendingPathComponent("\(name).\(ext)"),
                execDir.deletingLastPathComponent().appendingPathComponent("Resources/\(name).\(ext)"),
            ]
            for url in candidates where FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        // 3) 项目源目录回退（swift run 直接从项目根目录运行时）
        let sourceURL = URL(fileURLWithPath: "Sources/Resources/\(name).\(ext)")
        if FileManager.default.fileExists(atPath: sourceURL.path) {
            return sourceURL
        }

        return nil
    }
}
