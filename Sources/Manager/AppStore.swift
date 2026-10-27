import SwiftUI
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class AppStore {
    var page = "文件类型"
    var rows: [FileTypeRow] = []
    var apps: [AppInfo] = []
    var selected = Set<String>()
    var appSelection: String?
    var search = ""
    var searchRequest = 0
    var appSearch = ""
    var appOrigin = "全部"
    var category = "全部"
    var source = "全部"
    var appScope = "全部相关"
    var loading = false
    var error: String?
    var status = "准备就绪"
    var state = LocalState()
    var plan: [PlannedChange] = []
    var planSelection = Set<String>()
    var results: [OperationResult] = []
    var showPlan = false
    var showResults = false
    var busy = false
    var stop = false
    var restoring = false
    private var stateReadable = true
    let scanner = AppScanner()
    let descriptions = ExtensionDescriptionDB()

    init() {
        do { state = try StateFiles.read(); apps = state.apps } catch { stateReadable = false; self.error = "配置读取失败：\(error.localizedDescription)" }
    }
    var categories: [String] { ["全部"] + Set(rows.map(\.category)).sorted() }
    var selectedApp: AppInfo? { apps.first { $0.id == appSelection } }
    var visibleApps: [AppInfo] { apps.filter { app in
        (appSearch.isEmpty || app.name.localizedCaseInsensitiveContains(appSearch) || app.id.localizedCaseInsensitiveContains(appSearch)) && (appOrigin == "全部" || (appOrigin == "系统应用" ? app.isSystemApp : !app.isSystemApp))
    } }
    var filteredRows: [FileTypeRow] {
        rows.filter { row in
            let match = search.isEmpty || row.id.localizedCaseInsensitiveContains(RoutingRules.normalize(search)) || row.description.localizedCaseInsensitiveContains(search) || row.appName.localizedCaseInsensitiveContains(search)
            let cat = category == "全部" || row.category == category
            let origin = source == "全部" || (source == "系统应用" && row.isSystem) || (source == "第三方应用" && row.appID != nil && !row.isSystem) || (source == "未找到默认应用" && row.appID == nil)
            guard page == "应用", let app = selectedApp else { return match && cat && origin }
            let declared = app.supportedExtensions.contains(row.id)
            let current = row.appID == app.id
            return match && (appScope == "当前默认" ? current : appScope == "声明支持" ? declared : declared || current)
        }
    }
    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let loaded = await scanner.scanAllApps(forceRefresh: true)
        let info = await descriptions.allExtensionsInfo()
        var names = Set(info.map { RoutingRules.normalize($0.ext) })
        names.formUnion(loaded.flatMap(\.supportedExtensions))
        names.formUnion(state.records.flatMap(\.extensions))
        let lookup = Dictionary(info.map { (RoutingRules.normalize($0.ext), ($0.desc ?? "", $0.category ?? "其他")) }, uniquingKeysWith: { a, _ in a })
        var newRows: [FileTypeRow] = []
        for (i, ext) in names.sorted().enumerated() {
            guard let type = RoutingRules.typeID(ext) else { continue }
            let id = AssociationService.current(type)
            newRows.append(FileTypeRow(id: ext, typeID: type, description: lookup[ext]?.0 ?? "", category: lookup[ext]?.1 ?? "其他", appID: id, appName: AssociationService.name(id), isSystem: id?.hasPrefix("com.apple.") == true))
            if i % 30 == 0 { await Task.yield() }
        }
        apps = loaded.filter { ![RoutingRules.managerID, RoutingRules.receiverID].contains($0.id) }
        rows = newRows
        state.apps = apps
        persist()
        selected.formIntersection(Set(filteredRows.map(\.id)))
        status = "\(rows.count) 种格式 · 更新于 \(Date().formatted(date: .omitted, time: .shortened))"
    }
    func persist() {
        guard stateReadable else { return }
        do { try StateFiles.write(state) } catch { self.error = error.localizedDescription }
    }
    func prepare(_ exts: [String], target: String) {
        restoring = false
        plan = RoutingRules.plan(exts, target: target, current: AssociationService.current)
        presentPlan()
    }
    func prepareWeb() {
        restoring = false
        plan = ["http", "https"].map { PlannedChange(id: "scheme:\($0)", extensions: [], previousAppID: AssociationService.current("scheme:\($0)"), targetAppID: RoutingRules.receiverID) }
        presentPlan()
    }
    func prepareRestore(_ records: [AssociationRecord], fallback: String? = nil) {
        restoring = true
        plan = records.map { r in
            let current = AssociationService.current(r.id)
            let target = RoutingRules.recoveryTarget(record: r, current: current) ?? fallback ?? ""
            return PlannedChange(id: r.id, extensions: r.extensions, previousAppID: current, targetAppID: target,
                                 issue: target.isEmpty ? "请选择恢复应用" : nil)
        }
        presentPlan()
    }
    func presentPlan() {
        for i in plan.indices where plan[i].issue == nil {
            if AssociationService.appURL(plan[i].targetAppID) == nil { plan[i].issue = "目标应用未安装" }
        }
        planSelection = Set(plan.filter { $0.issue == nil }.map(\.id))
        showPlan = true
    }
    func execute() async {
        guard !busy else { return }
        guard stateReadable else { error = "本地恢复记录无法读取，请先修复配置文件"; return }
        busy = true; stop = false; results = []
        defer { busy = false }
        let changes = plan.filter { planSelection.contains($0.id) }
        let takeoverChanges = changes.filter { $0.targetAppID == RoutingRules.receiverID && !$0.id.hasPrefix("scheme:") }
        if !restoring && !takeoverChanges.isEmpty {
            do { try AssociationService.prepareBatchReceiver(for: takeoverChanges) }
            catch let batchError { self.error = batchError.localizedDescription; busy = false; return }
        }
        for change in changes {
            if stop { results.append(.init(id: change.id, label: change.label, status: .stopped, detail: "用户停止后续操作")); continue }
            let targetAppID = change.targetAppID == RoutingRules.receiverID && !change.id.hasPrefix("scheme:") ? RoutingRules.batchReceiverID : change.targetAppID
            let observedBefore = AssociationService.current(change.id)
            let registeredByBatch = !restoring && targetAppID == RoutingRules.batchReceiverID && RoutingRules.isReceiverID(observedBefore)
            let before = registeredByBatch ? change.previousAppID : observedBefore
            guard before == change.previousAppID || (RoutingRules.isReceiverID(before) && RoutingRules.isReceiverID(change.targetAppID)) else {
                results.append(.init(id: change.id, label: change.label, status: .failure, detail: "当前关联已改变，请重新预览")); continue
            }
            do {
                if registeredByBatch {
                    // Owner Receiver 的一次注册已经完成本批次全部 UTI 的接管。
                } else if before == targetAppID || (RoutingRules.isReceiverID(before) && RoutingRules.isReceiverID(targetAppID)) {
                    if restoring { state.records.removeAll { $0.id == change.id }; try StateFiles.write(state) }
                    results.append(.init(id: change.id, label: change.label, status: .skipped, detail: "当前已是所选应用")); continue
                }
                // 在系统写入前持久化恢复信息，即使中断也保留恢复入口。
                if !restoring {
                    if !state.records.contains(where: { $0.id == change.id && $0.targetAppID == change.targetAppID }) {
                        let prior = state.records.first { $0.id == change.id }
                        let recovery = RoutingRules.isReceiverID(before) ? prior?.previousAppID : before
                        state.records.removeAll { $0.id == change.id }
                        state.records.append(.init(id: change.id, extensions: change.extensions, previousAppID: recovery, targetAppID: targetAppID))
                    }
                    try StateFiles.write(state)
                }
                if !registeredByBatch {
                    try await AssociationService.write(change.id, appID: targetAppID)
                }
                var verified = RoutingRules.isReceiverID(targetAppID) ? RoutingRules.isReceiverID(AssociationService.current(change.id)) : AssociationService.current(change.id) == targetAppID
                for _ in 0..<4 where !verified {
                    try await Task.sleep(for: .milliseconds(150))
                    verified = RoutingRules.isReceiverID(targetAppID) ? RoutingRules.isReceiverID(AssociationService.current(change.id)) : AssociationService.current(change.id) == targetAppID
                }
                if verified && restoring { state.records.removeAll { $0.id == change.id }; try StateFiles.write(state) }
                results.append(.init(id: change.id, label: change.label, status: verified ? .success : .pending, detail: AssociationService.name(AssociationService.current(change.id))))
            } catch {
                results.append(.init(id: change.id, label: change.label, status: .failure, detail: error.localizedDescription))
            }
        }
        showPlan = false; showResults = true
        await refresh()
    }
    func exportConfig() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Openly_config.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var seen = Set<String>()
        var entries: [BackupConfig.Entry] = []
        for row in rows where seen.insert(row.typeID).inserted {
            guard let id = row.appID else { continue }
            let exts = rows.filter { $0.typeID == row.typeID }.map(\.id)
            entries.append(.init(uti: row.typeID, extensions: exts, bundleID: id, appName: row.appName, takeover: RoutingRules.isReceiverID(id)))
        }
        for scheme in ["http", "https"] where RoutingRules.isReceiverID(AssociationService.current("scheme:\(scheme)")) {
            entries.append(.init(extensions: [], bundleID: RoutingRules.receiverID, takeover: true, scheme: scheme))
        }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(BackupConfig(associations: entries)).write(to: url, options: .atomic); status = "已导出 \(url.lastPathComponent)" }
        catch { self.error = error.localizedDescription }
    }
    func importConfig() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let config = try JSONDecoder().decode(BackupConfig.self, from: Data(contentsOf: url))
            try RoutingRules.validate(config)
            var grouped: [String: PlannedChange] = [:]
            for entry in config.associations {
                let target = entry.takeover == true ? RoutingRules.receiverID : entry.bundleID
                let changes: [PlannedChange]
                if let scheme = entry.scheme {
                    guard ["http", "https"].contains(scheme) else { throw OpenlyError("不支持协议 \(scheme)") }
                    changes = [.init(id: "scheme:\(scheme)", extensions: [], previousAppID: AssociationService.current("scheme:\(scheme)"), targetAppID: target)]
                } else { changes = RoutingRules.plan(entry.extensions, target: target, current: AssociationService.current) }
                for var c in changes {
                    if let old = grouped[c.id], old.targetAppID != c.targetAppID { c.issue = "配置中同类型存在多个目标，请选择目标" }
                    grouped[c.id] = c
                }
            }
            plan = grouped.values.sorted { $0.id < $1.id }; restoring = false; presentPlan()
        } catch { self.error = "导入失败：\(error.localizedDescription)" }
    }
}
