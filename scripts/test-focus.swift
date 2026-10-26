import AppKit
import Foundation

@main struct FocusCheck {
    @MainActor static func main() async {
        do { try await run() } catch { FileHandle.standardError.write(Data("Focus check failed: \(error.localizedDescription)\n".utf8)); exit(1) }
    }
    @MainActor static func run() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fixture = root.appendingPathComponent(".build/checks/Openly UI Test.app")
        let output = root.appendingPathComponent(".build/checks/focus.json")
        try? FileManager.default.removeItem(at: output)
        let file = root.appendingPathComponent(".build/checks/打开验证.txt")
        try Data("Openly focus and grid verification\n".utf8).write(to: file)
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate(options: [.activateIgnoringOtherApps])
        try await Task.sleep(for: .milliseconds(200))
        let before = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        let config = NSWorkspace.OpenConfiguration(); config.activates = false; config.environment = ["OPENLY_FOCUS_LOG": output.path]
        _ = try await NSWorkspace.shared.open([file], withApplicationAt: fixture, configuration: config)
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: output.path) { try await Task.sleep(for: .milliseconds(50)) }
        let data = try Data(contentsOf: output)
        let state = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        print("source=\(before), receiver=\(state)")
        guard state["active"] as? Bool == true, state["keyWindow"] as? Bool == true, state["level"] as? Int == 0 else { throw NSError(domain: "Receiver not focused at normal level", code: 1) }
        print("PASS: Finder-origin open activates receiver and key window at normal level")
    }
}
