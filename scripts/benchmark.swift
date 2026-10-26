import AppKit
import Foundation

@main struct Benchmark {
    @MainActor static func main() async {
        do { try await run() } catch {
            FileHandle.standardError.write(Data("Benchmark stopped: \(error.localizedDescription)\n".utf8)); exit(1)
        }
    }
    @MainActor static func run() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let app = root.appendingPathComponent(".build/Openly.app/Contents/Helpers/Openly Receiver.app")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Openly-bench-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("probe.txt"); try Data("benchmark".utf8).write(to: file)
        var samples: [Double] = []
        for i in 0..<10 {
            guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.openly.receiver").isEmpty else { throw NSError(domain: "Close existing receiver before benchmark", code: 1) }
            let metric = folder.appendingPathComponent("\(i).txt")
            let config = NSWorkspace.OpenConfiguration(); config.activates = false
            config.environment = ["OPENLY_BENCHMARK": "1", "OPENLY_METRICS_PATH": metric.path, "OPENLY_BENCH_STARTED": String(ProcessInfo.processInfo.systemUptime)]
            let target = CommandLine.arguments.contains("--web") ? URL(string: "https://example.com/")! : file
            let running = try await NSWorkspace.shared.open([target], withApplicationAt: app, configuration: config)
            for _ in 0..<100 where !FileManager.default.fileExists(atPath: metric.path) { try await Task.sleep(for: .milliseconds(50)) }
            guard let value = Double(try String(contentsOf: metric, encoding: .utf8)) else { throw NSError(domain: "Missing metric", code: 2) }
            samples.append(value)
            for _ in 0..<100 where !running.isTerminated { try await Task.sleep(for: .milliseconds(50)) }
            guard running.isTerminated else { throw NSError(domain: "Receiver did not exit", code: 3) }
        }
        print("process-cold cached selector appearance ms: \(samples)")
        let ordered = samples.sorted()
        print("median=\(ordered[ordered.count / 2]) ms; maximum=\(ordered.last!) ms; runs=10")
    }
}
