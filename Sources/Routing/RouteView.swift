import SwiftUI
import AppKit

struct RouteView: View {
    @Bindable var model: RouterModel
    @NativeFocus private var searchFocused: Bool
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
        .onAppear { searchFocused = true; PerformanceProbe.visible() }
        .onChange(of: model.focusRequest) { searchFocused = true }
        .onChange(of: model.step) { searchFocused = true }
        .onExitCommand { if model.step == "apps" { model.onDismiss?() } else { model.backToApps() } }
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
                if model.step == "apps", let app = model.systemDefaultApp {
                    defaultAppButton(app)
                } else if (model.step == "options" || model.step == "advanced"), let app = model.selectedApp {
                    selectedAppSummary(app)
                }
            }
            Text(model.urls.map(\.absoluteString).joined(separator: "\n"))
                .font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                .accessibilityLabel("完整地址")
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
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
    }

    var appGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                TextField("搜索应用", text: $model.search)
                    .textFieldStyle(.roundedBorder).focused($searchFocused)
                    .accessibilityLabel("搜索应用名称、Bundle ID 或扩展名")
                Picker("筛选应用", selection: $model.onlyCompatible) {
                    Text("推荐").tag(true); Text("全部").tag(false)
                }
                .pickerStyle(.segmented).frame(width: 150)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            ScrollView([.horizontal, .vertical]) {
                LazyVGrid(columns: appColumns, alignment: .center, spacing: 4) {
                    ForEach(model.candidates) { app in
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
        HSplitView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(model.candidates) { app in
                        let isDefault = model.systemDefaultApp?.id == app.id
                        Button { model.selectApp(app.id) } label: {
                            HStack(spacing: 9) {
                                AppIcon(path: app.path, size: 34)
                                Text(app.name).font(.callout).lineLimit(1)
                                Spacer()
                            }
                            .frame(minHeight: 44).padding(.horizontal, 10)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("使用 \(app.name)\(isDefault ? "，原默认应用" : "")")
                    }
                }
                .padding(12)
            }
            .frame(minWidth: 190, idealWidth: 220, maxWidth: 250)
            optionGrid
        }
        .frame(minWidth: 680, minHeight: 360)
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
