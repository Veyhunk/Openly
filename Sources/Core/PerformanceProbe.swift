import Foundation
import AppKit

// 显式环境开关仅用于本机启动测量，常规运行不产生日志。
enum PerformanceProbe {
    static var enabled: Bool { ProcessInfo.processInfo.environment["OPENLY_BENCHMARK"] == "1" }
    static func visible() {
        let env = ProcessInfo.processInfo.environment
        guard enabled, let path = env["OPENLY_METRICS_PATH"], let raw = env["OPENLY_BENCH_STARTED"], let start = Double(raw) else { return }
        let duration = (ProcessInfo.processInfo.systemUptime - start) * 1000
        try? Data(String(format: "%.2f", duration).utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
    @MainActor static func recordFocus(_ window: NSWindow) {
        guard let path = ProcessInfo.processInfo.environment["OPENLY_FOCUS_LOG"] else { return }
        let state: [String: Any] = ["active": NSApp.isActive, "keyWindow": window.isKeyWindow, "level": window.level.rawValue]
        if let data = try? JSONSerialization.data(withJSONObject: state) { try? data.write(to: URL(fileURLWithPath: path), options: .atomic) }
    }

}
