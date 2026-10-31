import SwiftUI
import AppKit

enum RouteFocusTarget: Hashable { case search, defaultOpen, option(String) }

struct RouteView: View {
    @Bindable var model: RouterModel
    @NativeFocus private var focusedTarget: RouteFocusTarget?
    private let appColumns = Array(repeating: GridItem(.flexible(minimum: 106, maximum: 160), spacing: 8), count: 5)
    private let optionColumns = [GridItem(.adaptive(minimum: 220, maximum: 340), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.advancedMode { advancedLayout }
            else if model.step == "apps" { appGrid } else { optionGrid }
            Divider()
            footer
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 520, idealHeight: 520)
        .onAppear { focusInitial(); PerformanceProbe.visible() }
        .onChange(of: model.focusRequest) { focusInitial() }
        .onChange(of: model.step) { focusInitial() }
        .onExitCommand { if model.step == "apps" { model.onDismiss?() } else { model.backToApps() } }
        .onMoveCommand { direction in moveFocus(direction) }
        .background {
            Button("") { focusedTarget = .search }
                .keyboardShortcut("f", modifiers: [.command])
                .hidden()
        }
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if model.step == "options" {
                    Button { model.backToApps() } label: { Label("返回应用", systemImage: "chevron.left") }
                        .buttonStyle(.plain).disabled(model.busy)
                }
                Text(model.urls.count == 1 ? (model.urls[0].isFileURL ? model.urls[0].lastPathComponent : model.urls[0].host ?? model.urls[0].absoluteString) : "\(model.urls.count) 个项目")
                    .font(.title3).lineLimit(1)
                Spacer()
                if model.step == "apps", (!model.advancedMode || model.selectedApp == nil), let app = model.systemDefaultApp {
                    defaultAppButton(app)
                } else if (model.step == "options" || model.step == "advanced"), let app = model.selectedApp {
                    selectedAppSummary(app)
                }
            }
            HStack(alignment: .top, spacing: 6) {
                if model.urls.contains(where: \.isFileURL) {
                    Button { locateFiles() } label: {
                        Image(systemName: "location")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("在 Finder 中定位文件")
                    .accessibilityLabel("在 Finder 中定位文件")
                }
                Text(model.urls.map(displayAddress).joined(separator: "\n"))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityLabel("完整地址")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
    }

    func locateFiles() {
        let files = model.urls.filter(\.isFileURL)
        guard !files.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(files)
    }
    func focusInitial() {
        DispatchQueue.main.async {
            if model.advancedMode {
                if let option = firstAdvancedOption, let app = model.candidates.first(where: { model.options(for: $0).contains(where: { $0.id == option.id }) }) {
                    focusedTarget = .option("\(app.id):\(option.id)")
                } else { focusedTarget = .search }
            } else if model.step == "apps", model.systemDefaultApp != nil {
                focusedTarget = .defaultOpen
            } else { focusedTarget = .search }
        }
    }
    var firstAdvancedOption: RouteOption? {
        for app in model.candidates { if let option = model.options(for: app).first(where: { model.isOriginalDefault($0, app: app) }) { return option } }
        return model.candidates.first.flatMap { model.options(for: $0).first }
    }
    var optionFocusKeys: [String] {
        if model.advancedMode {
            return model.candidates.flatMap { app in model.options(for: app).map { "\(app.id):\($0.id)" } }
        }
        return model.availableOptions.map(\.id)
    }
    func moveFocus(_ direction: MoveCommandDirection) {
        guard !optionFocusKeys.isEmpty else { return }
        guard case .option(let current) = focusedTarget, let index = optionFocusKeys.firstIndex(of: current) else { return }
        let next: Int
        switch direction {
        case .left, .up: next = max(0, index - 1)
        case .right, .down: next = min(optionFocusKeys.count - 1, index + 1)
        @unknown default: return
        }
        focusedTarget = .option(optionFocusKeys[next])
    }
    func displayAddress(_ url: URL) -> String {
        url.isFileURL ? url.path : url.absoluteString
    }

    func selectedAppSummary(_ app: AppInfo) -> some View {
        HStack(spacing: 8) {
            AppIcon(path: app.path, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("已选择").font(.caption2).foregroundStyle(.secondary)
                Text(app.name).font(.callout).lineLimit(1)
            }
        }
        .frame(minWidth: 150, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("已选择应用 \(app.name)")
    }

    func defaultAppButton(_ app: AppInfo) -> some View {
        Button { Task { await model.openUsingSystemDefault() } } label: {
            HStack(spacing: 8) {
                AppIcon(path: app.path, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("默认打开").font(.callout.weight(.semibold))
                    Text(app.name).font(.caption)
                }
            }
            .frame(minWidth: 150, alignment: .leading)
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .disabled(model.busy)
        .help("使用系统默认应用 \(app.name) 打开")
        .accessibilityLabel("默认打开，使用 \(app.name)")
        .focused($focusedTarget, equals: .defaultOpen)
    }

    var appGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                TextField("搜索应用", text: $model.search)
                    .textFieldStyle(.roundedBorder).focused($focusedTarget, equals: .search)
                    .accessibilityLabel("搜索应用名称、Bundle ID 或扩展名")
                Picker("筛选应用", selection: $model.onlyCompatible) {
                    Text("推荐").tag(true); Text("全部").tag(false)
                }
                .pickerStyle(.segmented).frame(width: 150)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            ScrollView([.horizontal, .vertical]) {
                LazyVGrid(columns: appColumns, alignment: .center, spacing: 4) {
                    ForEach(model.candidates, id: \.id) { app in
                        let isDefault = model.systemDefaultApp?.id == app.id
                        Button { model.selectApp(app.id) } label: {
                            VStack(spacing: 4) {
                                AppIcon(path: app.path, size: 44)
                                Text(app.name).font(.callout).multilineTextAlignment(.center).lineLimit(2).frame(height: 34)
                                if isDefault { Text("原默认").font(.caption2).foregroundStyle(.tint) }
                            }
                            .frame(maxWidth: .infinity, minHeight: 72).padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RoutingAppTileButtonStyle())
                        .help(app.name)
                        .accessibilityLabel("使用 \(app.name)\(isDefault ? "，原默认应用" : "")，选择打开方式")
                    }
                }
                .padding(.horizontal, 22).padding(.bottom, 20)
                if model.candidates.isEmpty {
                    ContentUnavailableView("没有匹配的应用", systemImage: "square.grid.2x2", description: Text("可调整搜索条件，或查看全部应用。"))
                    if model.onlyCompatible { Button("查看全部应用") { model.onlyCompatible = false }.padding(.bottom, 12) }
                }
            }
        }
    }

    var advancedLayout: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TextField("搜索应用、窗口或打开方式", text: $model.search)
                    .textFieldStyle(.roundedBorder).focused($focusedTarget, equals: .search)
                Picker("筛选应用", selection: $model.onlyCompatible) { Text("推荐").tag(true); Text("全部").tag(false) }
                    .pickerStyle(.segmented).frame(width: 150)
            }.padding(.horizontal, 20).padding(.vertical, 10)
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.candidates, id: \.id) { app in
                        let options = model.options(for: app)
                        HStack(alignment: .top, spacing: 14) {
                            HStack(spacing: 8) { AppIcon(path: app.path, size: 34); Text(app.name).font(.callout).lineLimit(2) }
                                .frame(width: 150, alignment: .leading)
                                .frame(minHeight: 60, alignment: .leading)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) { ForEach(options) { option in advancedOptionButton(option, app: app) } }
                                    .padding(.vertical, 8)
                            }.focusSection()
                        }
                        .padding(.horizontal, 14)
                        .overlay(alignment: .bottom) { Divider() }
                    }
                }.padding(.horizontal, 8).padding(.bottom, 18)
            }
        }.frame(minWidth: 680, minHeight: 360)
    }

    func advancedOptionButton(_ option: RouteOption, app: AppInfo) -> some View {
        let isDefault = model.isOriginalDefault(option, app: app)
        return Button { Task { await model.choose(option, for: app) } } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(option.title).font(.callout.weight(.semibold)).lineLimit(1)
                Text(option.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }.frame(minWidth: 170, minHeight: 52, alignment: .leading).padding(.horizontal, 10)
        }
        .buttonStyle(RoutingOptionButtonStyle())
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isDefault ? Color.accentColor : Color.primary.opacity(0.10), lineWidth: isDefault ? 2 : 1))
        .focused($focusedTarget, equals: .option("\(app.id):\(option.id)"))
        .accessibilityLabel("\(app.name)，\(option.title)，\(option.detail)\(isDefault ? "，原默认打开方式" : "")")
    }

    var optionGrid: some View {
        VStack(spacing: 0) {
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 20) {
                    if model.selectedApp == nil {
                        ContentUnavailableView("选择一个应用", systemImage: "square.grid.2x2", description: Text("左侧选择应用后显示可行的打开方式。")).frame(minWidth: 420, minHeight: 180)
                    }
                    if let app = model.selectedApp, !model.supports(app) {
                        Text("此应用未声明支持全部所选内容，选择下方选项后尝试打开。").font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(model.optionSections, id: \.self) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section).font(.headline)
                            let columns = model.availableOptions.count == 1 ? [GridItem(.flexible(minimum: 420))] : optionColumns
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                                ForEach(model.availableOptions.filter { $0.section == section }) { option in
                                    let isDefault = model.isOriginalDefault(option)
                                    Button { Task { await model.choose(option) } } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(option.title).font(.headline).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                            Text(option.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                                        .padding(.horizontal, 12).padding(.vertical, 9)
                                    }
                                    .buttonStyle(RoutingOptionButtonStyle())
                                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                                    .overlay(alignment: .topTrailing) {
                                        if isDefault { Text("原默认").font(.caption2).foregroundStyle(.tint).padding(.horizontal, 7).padding(.vertical, 3).background(.thinMaterial, in: Capsule()).padding(7) }
                                    }
                                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(isDefault ? Color.accentColor : Color.primary.opacity(0.10), lineWidth: isDefault ? 2 : 1))
                                    .focused($focusedTarget, equals: .option(option.id))
                                    .disabled(model.busy)
                                    .help(option.title + " — " + option.detail)
                                    .accessibilityLabel("\(option.title)，\(option.detail)\(isDefault ? "，原默认打开方式" : "")")
                                }
                            }
                        }
                    }
                    if model.loadingTargets { HStack { ProgressView().controlSize(.small); Text("正在读取已有窗口和标签组，其他选项可直接使用。").foregroundStyle(.secondary) } }
                    if !WindowAccess.trusted { Button("授权后显示更多已有窗口") { WindowAccess.openSettings() } }
                    if model.chromium {
                        let id = model.selectedAppID ?? ""
                        Text(BrowserBridge.connectionHint(appID: id, extensionID: model.bridgeIDs[id])).font(.callout).foregroundStyle(.secondary)
                        if model.bridgeIDs[id] == nil { Text("先在管理界面的“打开接管 → 应用打开能力”中连接扩展。Profile 和默认／新窗口／无痕卡片仍可直接使用。").font(.caption).foregroundStyle(.secondary) }
                    }
                    ForEach(model.targetErrors.keys.sorted(), id: \.self) { name in
                        let message = model.targetErrors[name] ?? ""
                        Text("\(name)：\(message)").font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 22).padding(.bottom, 22)
            }
        }
    }

    var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = model.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if model.busy { ProgressView().controlSize(.small); Text("正在打开…") }
                else {
                    Text(model.step == "apps" ? (model.queue.isEmpty ? model.status : "另有 \(model.queue.count) 个请求待处理") : "点击打开方式即可执行")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if model.step == "apps" { Button("其他应用…") { chooseOtherApp() }.buttonStyle(.link).accessibilityLabel("选择其他应用") }
                Spacer()
                Button("取消") { model.onDismiss?() }.keyboardShortcut(.cancelAction).disabled(model.busy)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    func chooseOtherApp() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.application]
        if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier, ![RoutingRules.receiverID, RoutingRules.managerID].contains(id) {
            if !model.apps.contains(where: { $0.id == id }) { model.apps.append(.init(id: id, name: url.deletingPathExtension().lastPathComponent, path: url.path, version: nil, isSystemApp: false, supportedExtensions: [], iconPath: nil)) }
            model.selectApp(id)
        }
    }
}

struct RoutingAppTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.62 : 1).contentShape(Rectangle())
    }
}

struct RoutingOptionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.66 : 1).contentShape(Rectangle())
    }
}
