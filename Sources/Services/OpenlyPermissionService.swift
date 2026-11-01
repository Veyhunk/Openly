import AppKit
import ApplicationServices

enum OpenlyPermissionKind: String, CaseIterable, Identifiable, Sendable {
    case fullDiskAccess
    case accessibility
    case receiverAccessibility

    var id: String { rawValue }
    var title: String {
        switch self {
        case .fullDiskAccess: return "完全磁盘访问权限"
        case .accessibility: return "辅助功能权限"
        case .receiverAccessibility: return "辅助功能权限（Openly Receiver）"
        }
    }
    var purpose: String {
        switch self {
        case .fullDiskAccess: return "读取 Chrome / Edge 的 Local State，发现多个浏览器个人资料。"
        case .accessibility: return "读取已有窗口、标签组，并在选择后激活目标窗口。"
        case .receiverAccessibility: return "让实际接收文件和链接的 Openly Receiver 读取窗口并激活目标窗口。"
        }
    }
}

enum OpenlyPermissionState: Equatable, Sendable {
    case granted
    case missing
    case unavailable

    var label: String {
        switch self {
        case .granted: return "已授权"
        case .missing: return "未授权"
        case .unavailable: return "待检测"
        }
    }
}

@MainActor
enum OpenlyPermissionService {
    static let chromiumIDs = ["com.google.Chrome", "com.microsoft.edgemac", "org.chromium.Chromium", "com.google.Chrome.forTesting"]

    static func state(for kind: OpenlyPermissionKind) -> OpenlyPermissionState {
        switch kind {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .missing
        case .receiverAccessibility:
            guard let trusted = OpenlyPreferences.receiverAccessibilityTrusted else { return .unavailable }
            return trusted ? .granted : .missing
        case .fullDiskAccess:
            let states = chromiumIDs.map(BrowserService.profileAccessState)
            if states.contains(.denied) { return .missing }
            if states.contains(.available) { return .granted }
            return .unavailable
        }
    }

    static func missing(for appID: String) -> [OpenlyPermissionKind] {
        var result: [OpenlyPermissionKind] = []
        if BrowserService.isChromium(appID), BrowserService.profileAccessState(appID) == .denied { result.append(.fullDiskAccess) }
        if state(for: .accessibility) == .missing { result.append(.accessibility) }
        return result
    }

    static func openSystemSettings(for kind: OpenlyPermissionKind) {
        let fragment = kind == .fullDiskAccess ? "Privacy_AllFiles" : "Privacy_Accessibility"
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(fragment)") else { return }
        NSWorkspace.shared.open(url)
    }

    static func revealReceiverInFinder() {
        guard let receiver = ReceiverService.embeddedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([receiver])
    }

    static func openManagerPermissionPage() {
        OpenlyPreferences.requestManagerPage("权限设置")
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: RoutingRules.managerID) else { return }
        NSWorkspace.shared.open(app)
    }
}
