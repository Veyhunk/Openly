import Foundation

struct RouteOption: Identifiable, Sendable {
    let id: String
    let section: String
    let title: String
    let detail: String
    let symbol: String
    let mode: String
    var profile = "Default"
    var windowID: Int?
    var browserWindowID: Int?
    var groupID: Int?
}

extension RouterModel {
    var availableOptions: [RouteOption] {
        guard let app = selectedApp else { return [] }
        var options: [RouteOption] = []
        if chromium {
            for p in profiles {
                let section = "个人资料 · " + p.label
                for (mode, title, detail, symbol) in [
                    ("default", "默认打开", "使用此个人资料", "arrow.up.forward.app"),
                    ("new", "新窗口", "在此个人资料中新建窗口", "macwindow.badge.plus"),
                    ("incognito", "无痕窗口", "独立的无痕登录状态", "eye.slash")
                ] {
                    let optionDetail = mode == "default" ? p.label : detail
                    options.append(.init(id: p.id + ":" + mode, section: section, title: title, detail: optionDetail, symbol: symbol, mode: mode, profile: p.id))
                }
                if let snapshot = browserSnapshots[p.id] {
                    for window in snapshot.windows {
                        options.append(.init(id: "\(p.id):w\(window.id)", section: section, title: window.title, detail: "已有\(window.incognito ? "无痕" : "")窗口 · \(window.count) 个标签", symbol: "macwindow", mode: "browserWindow", profile: p.id, browserWindowID: window.id))
                        for group in snapshot.groups where group.windowId == window.id {
                            options.append(.init(id: "\(p.id):g\(group.id)", section: section, title: group.title, detail: "标签组 · \(window.title) · \(group.color)", symbol: "rectangle.stack", mode: "browserWindow", profile: p.id, browserWindowID: window.id, groupID: group.id))
                        }
                    }
                }
            }
            options.append(.init(id: "temporary", section: "临时浏览", title: "新建临时会话", detail: "使用全新的用户数据目录", symbol: "sparkle.magnifyingglass", mode: "temporary"))
        } else {
            options.append(.init(id: "default", section: "打开方式", title: vscode ? "最近活动窗口" : "默认打开", detail: "交给 \(app.name) 打开", symbol: "arrow.up.forward.app", mode: "default"))
            if vscode || genericNewWindow { options.append(.init(id: "new", section: "打开方式", title: "新窗口", detail: "在新窗口中打开", symbol: "macwindow.badge.plus", mode: "new")) }
        }
        if !chromium || browserSnapshots.values.allSatisfy({ $0.windows.isEmpty }) {
            for window in windows {
                options.append(.init(id: "ax:\(window.id)", section: "已有窗口", title: window.title, detail: vscode ? "切换到此窗口并打开" : "兼容打开 · 应用决定最终位置", symbol: "macwindow", mode: "window", windowID: window.id))
            }
        }
        return options.filter { optionSearch.isEmpty || ($0.section + " " + $0.title + " " + $0.detail).localizedCaseInsensitiveContains(optionSearch) }
    }
    var optionSections: [String] {
        var seen = Set<String>()
        return availableOptions.map(\.section).filter { seen.insert($0).inserted }
    }
    func choose(_ option: RouteOption) async {
        guard !busy else { return }
        mode = option.mode; profile = option.profile; windowID = option.windowID
        browserWindowID = option.browserWindowID; groupID = option.groupID
        allowUnsupported = true // 用户已明确选择该应用和打开动作。
        await openSelected()
    }
}
