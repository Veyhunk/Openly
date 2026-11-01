import AppKit

enum ReceiverStatus: Equatable, Sendable {
    case running
    case stopped
    case starting
    case stopping
    case unavailable

    var label: String {
        switch self {
        case .running: return "运行中"
        case .stopped: return "未运行"
        case .starting: return "正在启动"
        case .stopping: return "正在停止"
        case .unavailable: return "不可用"
        }
    }

    var symbol: String {
        switch self {
        case .running: return "checkmark.circle.fill"
        case .starting, .stopping: return "arrow.triangle.2.circlepath"
        case .stopped: return "pause.circle"
        case .unavailable: return "exclamationmark.triangle"
        }
    }
}

@MainActor
enum ReceiverService {
    static let bundleIDs = [RoutingRules.receiverID, RoutingRules.batchReceiverID]

    static var embeddedURL: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Openly Receiver.app")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static var isRunning: Bool {
        bundleIDs.contains { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
    }

    static func status() -> ReceiverStatus {
        guard embeddedURL != nil else { return .unavailable }
        return isRunning ? .running : .stopped
    }

    static func start() async -> ReceiverStatus {
        guard let receiver = embeddedURL else { return .unavailable }
        if isRunning { return .running }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", receiver.path]
        do { try process.run() } catch { return .unavailable }
        try? await Task.sleep(for: .milliseconds(350))
        return status()
    }

    static func stop() async -> ReceiverStatus {
        guard isRunning else { return status() }
        for bundleID in bundleIDs {
            for process in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
                process.terminate()
            }
        }
        try? await Task.sleep(for: .milliseconds(350))
        if isRunning {
            for bundleID in bundleIDs {
                for process in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
                    process.forceTerminate()
                }
            }
        }
        return status()
    }

    static func restart() async -> ReceiverStatus {
        _ = await stop()
        return await start()
    }

    static func stopImmediately() {
        for bundleID in bundleIDs {
            for process in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
                process.terminate()
                if !process.isTerminated { process.forceTerminate() }
            }
        }
    }
}
