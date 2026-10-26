import SwiftUI
import AppKit
import Observation

struct ManagerView: View {
    @Bindable var store: AppStore
    @NativeState private var showPicker = false
    @NativeState private var columnVisibility: NavigationSplitViewVisibility = .all
    @NativeFocus private var searchFocused: Bool
    @NativeState private var showInspector = false
    @NativeState private var sortOrder = [KeyPathComparator(\FileTypeRow.id)]
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $store.page) {
                Section("管理") {
                    Label("文件类型", systemImage: "doc.text").tag("文件类型")
                    Label("应用", systemImage: "square.grid.2x2").tag("应用")
                    Label("打开接管", systemImage: "arrow.triangle.branch").tag("打开接管")
                }
                Section("工具") { Label("检查文件", systemImage: "doc.text.magnifyingglass").tag("检查文件") }
            }.navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            VStack(spacing: 0) {
                if store.page == "打开接管" { TakeoverView(store: store) }
                else if store.page == "检查文件" { FileCheckView() }
                else if store.page == "应用" { appsView }
                else { typesView }
                Divider()
                HStack {
                    if store.loading { ProgressView().controlSize(.small) }
                    Text(store.status).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if !store.results.isEmpty { Button("查看上次结果") { store.showResults = true }.buttonStyle(.link) }
                }.padding(.horizontal, 16).frame(height: 32)
            }
            .navigationTitle(store.page)
        }
        .toolbar {
            ToolbarItem(id: "openly.sidebar", placement: .navigation) {
                Button {
                    withAnimation { columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly }
                } label: {
                    Label(columnVisibility == .detailOnly ? "显示侧栏" : "隐藏侧栏", systemImage: "sidebar.left")
                }
                .help(columnVisibility == .detailOnly ? "显示侧栏" : "隐藏侧栏")
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
            ToolbarItem(placement: .primaryAction) { Button { Task { await store.refresh() } } label: { Label("刷新", systemImage: "arrow.clockwise") }.disabled(store.loading || store.busy) }
            if ["文件类型", "应用"].contains(store.page) {
                ToolbarItem(placement: .primaryAction) { Button("更换默认应用…") { showPicker = true }.disabled(store.selected.isEmpty) }
                ToolbarItem(placement: .primaryAction) { Button("接管所选…") { store.prepare(Array(store.selected), target: RoutingRules.receiverID) }.disabled(store.selected.isEmpty) }
                ToolbarItem(placement: .primaryAction) { Button { showInspector.toggle() } label: { Label("详情", systemImage: "info.circle") } }
            }
        }
        .task { await store.refresh() }
        .onChange(of: store.searchRequest) { searchFocused = true }
        .onChange(of: store.page) { store.selected.removeAll(); store.search = "" }
        .onChange(of: store.search) { narrowSelection() }
        .onChange(of: store.category) { narrowSelection() }
        .onChange(of: store.source) { narrowSelection() }
        .onChange(of: store.appScope) { narrowSelection() }
        .onChange(of: store.appSelection) { store.selected.removeAll() }
        .sheet(isPresented: $showPicker) { AppPicker(store: store) { id in showPicker = false; store.prepare(Array(store.selected), target: id) } }
        .sheet(isPresented: $store.showPlan) { PlanView(store: store) }
        .sheet(isPresented: $store.showResults) { ResultsView(store: store) }
        .alert("操作未完成", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("好") { store.error = nil } } message: { Text(store.error ?? "") }
    }
    func narrowSelection() { store.selected.formIntersection(Set(store.filteredRows.map(\.id))) }
    var typesView: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("搜索扩展名、说明或应用", text: $store.search).textFieldStyle(.roundedBorder).focused($searchFocused)
                Picker("分类", selection: $store.category) { ForEach(store.categories, id: \.self) { Text($0) } }.frame(width: 170)
                Picker("默认应用", selection: $store.source) { ForEach(["全部", "系统应用", "第三方应用", "未找到默认应用"], id: \.self) { Text($0) } }.frame(width: 210)
                if !store.search.isEmpty || store.category != "全部" || store.source != "全部" {
                    Button("清除") { store.search = ""; store.category = "全部"; store.source = "全部" }
                }
            }.padding(16)
            typeTable
        }
    }
    var typeTable: some View {
        VStack(spacing: 0) {
            Table(store.filteredRows.sorted(using: sortOrder), selection: $store.selected, sortOrder: $sortOrder) {
                TableColumn("文件类型", value: \.id) { row in Text("." + row.id).monospaced() }.width(min: 75, ideal: 110)
                TableColumn("说明", value: \.description).width(min: 100, ideal: 200)
                TableColumn("默认应用", value: \.appName) { row in
                    HStack { if row.appID == RoutingRules.receiverID { Image(systemName: "arrow.triangle.branch") }; Text(row.appName) }
                }.width(min: 140, ideal: 220)
                TableColumn("分类", value: \.category).width(min: 60, ideal: 90)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                Button("更换默认应用…") { store.selected = ids; showPicker = true }.disabled(ids.isEmpty)
                Button("交给 Openly 接管…") { store.prepare(Array(ids), target: RoutingRules.receiverID) }.disabled(ids.isEmpty)
                Button("恢复修改前设置…") {
                    let types = Set(store.rows.filter { ids.contains($0.id) }.map(\.typeID))
                    store.prepareRestore(store.state.records.filter { types.contains($0.id) })
                }.disabled(!store.state.records.contains { r in store.rows.contains { ids.contains($0.id) && $0.typeID == r.id } })
            } primaryAction: { ids in store.selected = ids; showPicker = true }
            .overlay { if store.filteredRows.isEmpty && !store.loading { ContentUnavailableView("没有匹配的文件类型", systemImage: "doc.text.magnifyingglass", description: Text("调整搜索或筛选条件")) } }
            if showInspector, let row = store.rows.first(where: { store.selected.contains($0.id) }) {
                GroupBox("类型详情") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(row.typeID).monospaced().textSelection(.enabled)
                        Text("默认应用：\(row.appName)")
                        Text("同类型后缀：" + store.rows.filter { $0.typeID == row.typeID }.map { "." + $0.id }.joined(separator: "、"))
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(12)
            }
            HStack { Text("显示 \(store.filteredRows.count) 种格式 · 已选 \(store.selected.count) 种").font(.caption).foregroundStyle(.secondary); Spacer() }.padding(10)
        }
    }
    var appsView: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    TextField("搜索应用", text: $store.appSearch).textFieldStyle(.roundedBorder).focused($searchFocused)
                    Button { store.appSearch = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).opacity(store.appSearch.isEmpty ? 0 : 1)
                }.padding(.horizontal, 12).padding(.top, 12)
                Picker("来源", selection: $store.appOrigin) { ForEach(["全部", "系统应用", "第三方应用"], id: \.self) { Text($0) } }.pickerStyle(.segmented).padding(12)
                Divider()
                List(store.visibleApps, selection: $store.appSelection) { app in
                    HStack(spacing: 9) {
                        AppIcon(path: app.path)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name).lineLimit(1)
                            Text("默认打开 \(store.rows.filter { $0.appID == app.id }.count) 种").font(.caption).foregroundStyle(.secondary)
                        }
                    }.tag(app.id).padding(.vertical, 3)
                }.listStyle(.sidebar)
            }
            .frame(minWidth: 230, idealWidth: 270, maxWidth: 310, maxHeight: .infinity)
            .background(Color(nsColor: .underPageBackgroundColor))

            appDetailPane
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    var appDetailPane: some View {
        if let app = store.selectedApp {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    AppIcon(path: app.path, size: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name).font(.title2)
                        Text("版本 \(app.version ?? "—") · 声明支持 \(app.supportedExtensions.count) 种")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)]) }
                }.padding(.horizontal, 20).padding(.vertical, 16)
                Text(app.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).padding(.horizontal, 20).padding(.bottom, 12)
                Divider()
                HStack(spacing: 10) {
                    Picker("范围", selection: $store.appScope) { ForEach(["全部相关", "当前默认", "声明支持"], id: \.self) { Text($0) } }.pickerStyle(.segmented).frame(width: 260)
                    TextField("搜索格式", text: $store.search).textFieldStyle(.roundedBorder)
                    Button("设为默认…") { store.prepare(Array(store.selected), target: app.id) }.disabled(store.selected.isEmpty)
                }.padding(14)
                appTypeTable(app)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ContentUnavailableView("选择一个应用", systemImage: "square.grid.2x2", description: Text("查看声明支持与当前默认的文件类型"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    func appTypeTable(_ app: AppInfo) -> some View {
        VStack(spacing: 0) {
            Table(store.filteredRows, selection: $store.selected) {
                TableColumn("文件类型") { row in Text("." + row.id).monospaced() }.width(min: 80, ideal: 105, max: 140)
                TableColumn("说明") { row in Text(row.description).lineLimit(1) }.width(min: 120, ideal: 210, max: 280)
                TableColumn("当前默认") { row in Text(row.appName).lineLimit(1) }.width(min: 110, ideal: 165, max: 220)
                TableColumn("关系") { row in
                    let current = row.appID == app.id
                    let declared = app.supportedExtensions.contains(row.id)
                    Text(current && declared ? "默认 · 声明支持" : current ? "当前默认" : declared ? "声明支持" : "相关")
                        .foregroundStyle(current ? Color.accentColor : Color.secondary)
                }.width(min: 100, ideal: 135, max: 180)
            }
            .overlay { if store.filteredRows.isEmpty && !store.loading { ContentUnavailableView("没有匹配的格式", systemImage: "doc.text.magnifyingglass", description: Text("调整范围或搜索条件")) } }
            HStack {
                Text("显示 \(store.filteredRows.count) 种格式 · 已选 \(store.selected.count) 种").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }.padding(.horizontal, 14).frame(height: 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

struct AppIcon: View {
    let path: String
    var size: CGFloat = 22
    var body: some View { Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: size, height: size).accessibilityHidden(true) }
}

struct AppPicker: View {
    var store: AppStore
    let onChoose: (String) -> Void
    @Environment(\.dismiss) var dismiss
    @NativeState private var search = ""
    @NativeState private var selected: String?
    @NativeState private var allowUnverified = false
    var compatible: Bool {
        guard let app = store.apps.first(where: { $0.id == selected }) else { return false }
        return store.selected.allSatisfy { app.supportedExtensions.contains($0) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("更换默认应用").font(.title2)
            Text("已选 \(store.selected.count) 种格式，下一步预览实际影响范围。").foregroundStyle(.secondary)
            TextField("搜索应用", text: $search).textFieldStyle(.roundedBorder)
            List(store.apps.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }, selection: $selected) { app in
                HStack { AppIcon(path: app.path); Text(app.name); Spacer(); Text("支持 \(store.selected.filter { app.supportedExtensions.contains($0) }.count)/\(store.selected.count)").foregroundStyle(.secondary) }.tag(app.id)
            }
            if selected != nil && !compatible { Toggle("支持情况待确认，仍使用此应用", isOn: $allowUnverified) }
            HStack {
                Button("选择其他应用…") {
                    let panel = NSOpenPanel(); panel.allowedContentTypes = [.application]
                    if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier { onChoose(id) }
                }
                Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("预览更改") { if let selected { onChoose(selected) } }.keyboardShortcut(.defaultAction).disabled(selected == nil || (!compatible && !allowUnverified))
            }
        }.padding(24).frame(width: 580, height: 510)
    }
}

struct PlanView: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(store.restoring ? "预览恢复范围" : "预览更改范围").font(.title2)
            Text("\(store.plan.count) 个文件类型或协议 · 同类型别名会一并生效").foregroundStyle(.secondary)
            List {
                ForEach(store.plan) { change in
                    HStack {
                        Toggle("选择 \(change.label)", isOn: Binding(get: { store.planSelection.contains(change.id) }, set: { if $0 { store.planSelection.insert(change.id) } else { store.planSelection.remove(change.id) } })).labelsHidden().disabled(change.issue != nil || store.busy)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(change.label).fontWeight(.medium)
                            Text("\(AssociationService.name(change.previousAppID)) → \(AssociationService.name(change.targetAppID))").font(.callout).foregroundStyle(.secondary)
                            if let issue = change.issue { Text(issue).foregroundStyle(.red) }
                        }
                        Spacer()
                        if !store.busy {
                            Menu("更改目标") {
                                ForEach(store.apps) { app in Button(app.name) {
                                    if let i = store.plan.firstIndex(where: { $0.id == change.id }) {
                                        store.plan[i].targetAppID = app.id; store.plan[i].issue = nil; store.planSelection.insert(change.id)
                                    }
                                } }
                            }.frame(width: 100)
                        }
                    }.padding(.vertical, 5)
                }
            }
            HStack {
                if store.busy { ProgressView().controlSize(.small); Text("已处理 \(store.results.count) 项"); Spacer(); Button("停止后续操作") { store.stop = true } }
                else { Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Button("应用所选 \(store.planSelection.count) 项") { Task { await store.execute() } }.keyboardShortcut(.defaultAction).disabled(store.planSelection.isEmpty) }
            }
        }.padding(24).frame(width: 680, height: 510).interactiveDismissDisabled(store.busy)
    }
}

struct ResultsView: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("操作结果").font(.title2)
            Text(Dictionary(grouping: store.results, by: \.status).map { "\($0.key.rawValue) \($0.value.count)" }.sorted().joined(separator: " · ")).foregroundStyle(.secondary)
            List(store.results) { r in HStack(alignment: .top) { Text(r.label).frame(width: 150, alignment: .leading); Text(r.status.rawValue).frame(width: 70); Text(r.detail).foregroundStyle(r.status == .failure ? Color.red : Color.secondary).textSelection(.enabled) } }
            HStack {
                Button("复制结果") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.results.map { "\($0.label)\t\($0.status.rawValue)\t\($0.detail)" }.joined(separator: "\n"), forType: .string) }
                Button("重新验证") {
                    for i in store.results.indices where store.results[i].status == .pending {
                        if let p = store.plan.first(where: { $0.id == store.results[i].id }), AssociationService.current(p.id) == p.targetAppID { store.results[i].status = .success }
                    }
                }
                Button("重试失败项") {
                    let failed = Set(store.results.filter { $0.status == .failure }.map(\.id))
                    store.plan = store.plan.filter { failed.contains($0.id) }.map { p in var p = p; p.previousAppID = AssociationService.current(p.id); return p }
                    store.showResults = false; store.presentPlan()
                }.disabled(!store.results.contains { $0.status == .failure })
                Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 680, height: 460)
    }
}
