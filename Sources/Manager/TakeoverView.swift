import SwiftUI
import AppKit

struct TakeoverView: View {
    @Bindable var store: AppStore
    @NativeState private var showAdd = false
    @NativeState private var selection = Set<String>()
    @NativeState private var search = ""
    @NativeState private var stateFilter = "全部"
    @NativeState private var sortOrder = [KeyPathComparator(\AssociationRecord.id)]
    @NativeState private var bridgeApp = "com.google.Chrome"
    @NativeState private var extensionID = ""
    var records: [AssociationRecord] {
        store.state.records.filter { record in
            guard RoutingRules.isReceiverID(record.targetAppID), !record.id.hasPrefix("scheme:") else { return false }
            let claimed = RoutingRules.isReceiverID(AssociationService.current(record.id))
            let matchesState = stateFilter == "全部" || (stateFilter == "已接管" && claimed) || (stateFilter == "未接管" && !claimed)
            return matchesState && (search.isEmpty || record.extensions.joined(separator: " ").localizedCaseInsensitiveContains(search) || record.id.localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("文件后缀").font(.title2); Spacer(); Button("添加接管后缀…") { showAdd = true }.buttonStyle(.borderedProminent) }
            Text("打开时由你选择应用。关闭管理窗口后仍可按需接收打开请求。").foregroundStyle(.secondary)
            HStack {
                TextField("搜索接管后缀", text: $search).textFieldStyle(.roundedBorder)
                Picker("状态", selection: $stateFilter) {
                    Text("全部").tag("全部")
                    Text("已接管").tag("已接管")
                    Text("未接管").tag("未接管")
                }.pickerStyle(.segmented).labelsHidden().frame(width: 225)
            }
            Table(records.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
                TableColumn("后缀", value: \.id) { r in Text(r.extensions.map { "." + $0 }.joined(separator: ", ")) }
                TableColumn("常用", value: \.commonSortKey) { r in
                    if r.extensions.contains(where: ExtensionUsage.isCommon) { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                }.width(min: 42, ideal: 48, max: 56)
                TableColumn("接管前应用", value: \.previousAppSortKey) { r in Text(AssociationService.name(r.previousAppID)) }
                TableColumn("当前状态", value: \.statusSortKey) { r in Text(RoutingRules.isReceiverID(AssociationService.current(r.id)) ? "已接管" : "已被更改 / 未生效") }
            }.frame(minHeight: 150)
            HStack { Text("\(records.count) 个系统类型 · 已选 \(selection.count) 项").foregroundStyle(.secondary); Spacer(); Button("停止所选接管…") { store.prepareRestore(records.filter { selection.contains($0.id) }) }.disabled(selection.isEmpty); Button("停止全部接管…") { store.prepareRestore(store.state.records.filter { RoutingRules.isReceiverID($0.targetAppID) }) }.disabled(!store.state.records.contains { RoutingRules.isReceiverID($0.targetAppID) }) }
            GroupBox("网页链接") {
                HStack {
                    VStack(alignment: .leading) { ForEach(["http", "https"], id: \.self) { Text("\($0.uppercased())：\(AssociationService.name(AssociationService.current("scheme:" + $0)))") } }
                    Spacer(); Button("启用网页接管…") { store.prepareWeb() }
                    Button("恢复网页打开…") { store.prepareRestore(store.state.records.filter { $0.id.hasPrefix("scheme:") }) }.disabled(!store.state.records.contains { $0.id.hasPrefix("scheme:") })
                }.padding(8)
            }
            GroupBox("应用打开能力") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text("窗口选择"); Spacer(); Text(WindowAccess.trusted ? "管理程序已获辅助功能权限" : "管理程序未获辅助功能权限").foregroundStyle(WindowAccess.trusted ? .green : .secondary); Button("前往系统设置") { WindowAccess.openSettings() } }
                    Text("权限按应用身份分别保存。请在列表中授权 Openly Receiver；它位于 Openly.app/Contents/Helpers/。授权后重新打开接管窗口，窗口数量会显示在高级卡片中。").font(.caption).foregroundStyle(.secondary)
                    HStack { Image(systemName: WindowAccess.trusted ? "checkmark.circle.fill" : "info.circle"); Text(WindowAccess.receiverStatusText).font(.caption) }
                    Divider()
                    Text("Chrome / Edge 的窗口与标签组通过每个个人资料中安装的 Openly 浏览器扩展连接。").foregroundStyle(.secondary)
                    if let configured = store.state.bridgeIDs[bridgeApp] { Text(BrowserBridge.connectionHint(appID: bridgeApp, extensionID: configured)).font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        Picker("浏览器", selection: $bridgeApp) { Text("Chrome").tag("com.google.Chrome"); Text("Edge").tag("com.microsoft.edgemac") }.frame(width: 170)
                        TextField("已安装扩展的 ID", text: $extensionID).textFieldStyle(.roundedBorder)
                        Button("连接扩展") {
                            do { try BrowserBridge.install(appID: bridgeApp, extensionID: extensionID); store.state.bridgeIDs[bridgeApp] = extensionID; store.persist(); store.status = BrowserBridge.connectionHint(appID: bridgeApp, extensionID: extensionID) } catch { store.error = error.localizedDescription }
                        }.disabled(!BrowserBridge.validExtensionID(extensionID))
                    }
                    Button("打开扩展文件夹与安装说明") {
                        let url = Bundle.main.resourceURL?.appendingPathComponent("BrowserExtension") ?? URL(fileURLWithPath: "BrowserExtension")
                        NSWorkspace.shared.open(url)
                    }.buttonStyle(.link)
                }.padding(8)
            }
        }.padding(24)
        .sheet(isPresented: $showAdd) { TakeoverSelection(store: store) }
    }
}

struct TakeoverSelection: View {
    var store: AppStore
    @Environment(\.dismiss) var dismiss
    @NativeState private var mode = "按类型"
    @NativeState private var category = "全部"
    @NativeState private var appID = ""
    @NativeState private var scope = "声明支持"
    @NativeState private var search = ""
    @NativeState private var selected = Set<String>()
    @NativeState private var onlySelected = false
    @NativeState private var commonOnly = false
    var candidates: [FileTypeRow] {
        let app = store.apps.first { $0.id == appID }
        return store.rows.filter { row in
            if onlySelected { return selected.contains(row.id) }
            guard search.isEmpty || row.id.localizedCaseInsensitiveContains(RoutingRules.normalize(search)) || row.description.localizedCaseInsensitiveContains(search) else { return false }
            if commonOnly && !row.isCommon { return false }
            if mode == "按类型" { return category == "全部" || row.category == category }
            guard let app else { return false }
            let declared = app.supportedExtensions.contains(row.id), current = row.appID == app.id
            return scope == "声明支持" ? declared : scope == "当前默认" ? current : declared || current
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("添加接管后缀").font(.title2)
            HStack { Picker("来源", selection: $mode) { Text("按类型").tag("按类型"); Text("按应用").tag("按应用") }.pickerStyle(.segmented); TextField("搜索后缀或说明", text: $search).textFieldStyle(.roundedBorder); Picker("常用", selection: $commonOnly) { Text("全部").tag(false); Text("常用").tag(true) }.pickerStyle(.segmented).frame(width: 120) }
            HSplitView {
                if mode == "按类型" { List(store.categories, id: \.self, selection: $category) { Text($0) }.frame(width: 160) }
                else { List(store.apps, selection: $appID) { Text($0.name).tag($0.id) }.frame(width: 180) }
                VStack {
                    if mode == "按应用" { Picker("范围", selection: $scope) { ForEach(["声明支持", "当前默认", "全部相关"], id: \.self) { Text($0) } }.pickerStyle(.segmented) }
                    HStack {
                        Button("全选当前结果") { selected.formUnion(candidates.filter { !RoutingRules.isReceiverID($0.appID) }.map(\.id)) }
                        Button("常用全选") { selected.formUnion(candidates.filter { $0.isCommon && !RoutingRules.isReceiverID($0.appID) }.map(\.id)) }
                        Button("取消全选") { selected.removeAll() }; Spacer()
                    }
                    List(candidates) { row in
                        Toggle(isOn: Binding(get: { selected.contains(row.id) }, set: { if $0 { selected.insert(row.id) } else { selected.remove(row.id) } })) {
                            HStack {
                                Text("." + row.id).monospaced().frame(width: 85, alignment: .leading)
                                if row.isCommon { Image(systemName: "star.fill").foregroundStyle(.yellow).help("常用").frame(width: 20) }
                                Text(row.description)
                                Spacer()
                                Text(row.appName).foregroundStyle(.secondary)
                            }
                        }.disabled(RoutingRules.isReceiverID(row.appID))
                    }
                }
            }
            HStack { Text("已选 \(selected.count) 种 · 当前可见 \(candidates.filter { selected.contains($0.id) }.count) 种"); Toggle("查看已选", isOn: $onlySelected); Button("清空") { selected.removeAll() }; Spacer() }
            HStack { Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Button("预览接管范围") { dismiss(); store.prepare(Array(selected), target: RoutingRules.receiverID) }.keyboardShortcut(.defaultAction).disabled(selected.isEmpty) }
        }.padding(24).frame(width: 790, height: 550)
    }
}
