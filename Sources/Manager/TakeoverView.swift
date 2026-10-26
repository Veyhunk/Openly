import SwiftUI
import AppKit

struct TakeoverView: View {
    @Bindable var store: AppStore
    @NativeState private var showAdd = false
    @NativeState private var selection = Set<String>()
    @NativeState private var search = ""
    @NativeState private var bridgeApp = "com.google.Chrome"
    @NativeState private var extensionID = ""
    var records: [AssociationRecord] { store.state.records.filter { $0.targetAppID == RoutingRules.receiverID && !$0.id.hasPrefix("scheme:") && (search.isEmpty || $0.extensions.joined(separator: " ").localizedCaseInsensitiveContains(search)) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("文件后缀").font(.title2); Spacer(); Button("添加接管后缀…") { showAdd = true }.buttonStyle(.borderedProminent) }
            Text("打开时由你选择应用。关闭管理窗口后仍可按需接收打开请求。").foregroundStyle(.secondary)
            TextField("搜索接管后缀", text: $search).textFieldStyle(.roundedBorder)
            Table(records, selection: $selection) {
                TableColumn("后缀") { r in Text(r.extensions.map { "." + $0 }.joined(separator: ", ")) }
                TableColumn("接管前应用") { r in Text(AssociationService.name(r.previousAppID)) }
                TableColumn("当前状态") { r in Text(AssociationService.current(r.id) == RoutingRules.receiverID ? "已接管" : "已被更改 / 未生效") }
            }.frame(minHeight: 150)
            HStack { Text("\(records.count) 个系统类型 · 已选 \(selection.count) 项").foregroundStyle(.secondary); Spacer(); Button("停止所选接管…") { store.prepareRestore(records.filter { selection.contains($0.id) }) }.disabled(selection.isEmpty); Button("停止全部接管…") { store.prepareRestore(store.state.records.filter { $0.targetAppID == RoutingRules.receiverID }) }.disabled(!store.state.records.contains { $0.targetAppID == RoutingRules.receiverID }) }
            GroupBox("网页链接") {
                HStack {
                    VStack(alignment: .leading) { ForEach(["http", "https"], id: \.self) { Text("\($0.uppercased())：\(AssociationService.name(AssociationService.current("scheme:" + $0)))") } }
                    Spacer(); Button("启用网页接管…") { store.prepareWeb() }
                    Button("恢复网页打开…") { store.prepareRestore(store.state.records.filter { $0.id.hasPrefix("scheme:") }) }.disabled(!store.state.records.contains { $0.id.hasPrefix("scheme:") })
                }.padding(8)
            }
            GroupBox("应用打开能力") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text("窗口选择"); Spacer(); Text("请为 Openly Receiver 授予辅助功能权限").foregroundStyle(.secondary); Button("前往系统设置") { WindowAccess.openSettings() } }
                    Divider()
                    Text("Chrome / Edge 的窗口与标签组通过 Openly 浏览器扩展连接。").foregroundStyle(.secondary)
                    HStack {
                        Picker("浏览器", selection: $bridgeApp) { Text("Chrome").tag("com.google.Chrome"); Text("Edge").tag("com.microsoft.edgemac") }.frame(width: 170)
                        TextField("已安装扩展的 ID", text: $extensionID).textFieldStyle(.roundedBorder)
                        Button("连接扩展") {
                            do { try BrowserBridge.install(appID: bridgeApp, extensionID: extensionID); store.state.bridgeIDs[bridgeApp] = extensionID; store.persist(); store.status = "已配置扩展连接" } catch { store.error = error.localizedDescription }
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
    var candidates: [FileTypeRow] {
        let app = store.apps.first { $0.id == appID }
        return store.rows.filter { row in
            if onlySelected { return selected.contains(row.id) }
            guard search.isEmpty || row.id.localizedCaseInsensitiveContains(RoutingRules.normalize(search)) || row.description.localizedCaseInsensitiveContains(search) else { return false }
            if mode == "按类型" { return category == "全部" || row.category == category }
            guard let app else { return false }
            let declared = app.supportedExtensions.contains(row.id), current = row.appID == app.id
            return scope == "声明支持" ? declared : scope == "当前默认" ? current : declared || current
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("添加接管后缀").font(.title2)
            HStack { Picker("来源", selection: $mode) { Text("按类型").tag("按类型"); Text("按应用").tag("按应用") }.pickerStyle(.segmented); TextField("搜索后缀或说明", text: $search).textFieldStyle(.roundedBorder) }
            HSplitView {
                if mode == "按类型" { List(store.categories, id: \.self, selection: $category) { Text($0) }.frame(width: 160) }
                else { List(store.apps, selection: $appID) { Text($0.name).tag($0.id) }.frame(width: 180) }
                VStack {
                    if mode == "按应用" { Picker("范围", selection: $scope) { ForEach(["声明支持", "当前默认", "全部相关"], id: \.self) { Text($0) } }.pickerStyle(.segmented) }
                    HStack {
                        Button("全选当前结果") { selected.formUnion(candidates.filter { $0.appID != RoutingRules.receiverID }.map(\.id)) }
                        Button("取消当前结果") { selected.subtract(candidates.map(\.id)) }; Spacer()
                    }
                    List(candidates) { row in
                        Toggle(isOn: Binding(get: { selected.contains(row.id) }, set: { if $0 { selected.insert(row.id) } else { selected.remove(row.id) } })) {
                            HStack { Text("." + row.id).monospaced().frame(width: 85, alignment: .leading); Text(row.description); Spacer(); Text(row.appName).foregroundStyle(.secondary) }
                        }.disabled(row.appID == RoutingRules.receiverID)
                    }
                }
            }
            HStack { Text("已选 \(selected.count) 种 · 当前可见 \(candidates.filter { selected.contains($0.id) }.count) 种"); Toggle("查看已选", isOn: $onlySelected); Button("清空") { selected.removeAll() }; Spacer() }
            HStack { Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Button("预览接管范围") { dismiss(); store.prepare(Array(selected), target: RoutingRules.receiverID) }.keyboardShortcut(.defaultAction).disabled(selected.isEmpty) }
        }.padding(24).frame(width: 790, height: 550)
    }
}
