import SwiftUI
import AppKit

struct RouteView: View {
    @Bindable var model: RouterModel
    @NativeFocus private var searchFocused: Bool
    private let appColumns = Array(repeating: GridItem(.flexible(minimum: 100, maximum: 150), spacing: 12), count: 5)
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
        .frame(minWidth: 760, minHeight: 420)
        .onAppear { searchFocused = true; PerformanceProbe.visible() }
        .onChange(of: model.focusRequest) { searchFocused = true }
        .onChange(of: model.step) { searchFocused = true }
    }
    var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if model.step == "options" || model.step == "advanced" {
                    if model.step == "options" { Button { model.backToApps() } label: { Label("返回应用", systemImage: "chevron.left") }.buttonStyle(.plain).disabled(model.busy) }
                }
                Text(model.urls.count == 1 ? (model.urls[0].isFileURL ? model.urls[0].lastPathComponent : model.urls[0].host ?? model.urls[0].absoluteString) : "\(model.urls.count) 个项目")
                    .font(.title3).lineLimit(1)
                Spacer()
                if model.step == "apps", let app = model.systemDefaultApp {
                    defaultAppButton(app)
                } else if (model.step == "options" || model.step == "advanced"), let app = model.selectedApp {
                    HStack(spacing: 7) { AppIcon(path: app.path, size: 26); Text(app.name).font(.callout).lineLimit(1) }
                }
            }
            Text(model.urls.map(\.absoluteString).joined(separator: "\n"))
                .font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
        }.padding(20)
    }
    func defaultAppButton(_ app: AppInfo) -> some View {
        Button { Task { await model.openUsingSystemDefault() } } label: {
            HStack(spacing: 8) {
                AppIcon(path: app.path, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("按默认方式打开").font(.headline)
                    Text(app.name).font(.caption)
                }
            }.frame(minWidth: 190, alignment: .leading)
        }.buttonStyle(.borderedProminent).disabled(model.busy).help("使用系统默认应用 \(app.name) 打开")
    }
    var appGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                TextField("搜索应用", text: $model.search).textFieldStyle(.roundedBorder).focused($searchFocused)
                Picker("显示", selection: $model.onlyCompatible) { Text("推荐").tag(true); Text("全部").tag(false) }.pickerStyle(.segmented).labelsHidden().frame(width: 150)
            }.padding(.horizontal, 20).padding(.vertical, 14)
            ScrollView {
                LazyVGrid(columns: appColumns, alignment: .center, spacing: 18) {
                    ForEach(model.candidates) { app in
                        let isDefault = model.systemDefaultApp?.id == app.id
                        Button { model.selectApp(app.id) } label: {
                            VStack(spacing: 9) {
                                AppIcon(path: app.path, size: 54)
                                Text(app.name).font(.callout).multilineTextAlignment(.center).lineLimit(2).frame(height: 34)
                            }.frame(maxWidth: .infinity).padding(.vertical, 8).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .topTrailing) {
                            if isDefault { Text("原默认").font(.caption2).foregroundStyle(.tint).padding(.horizontal, 7).padding(.vertical, 3).background(.thinMaterial, in: Capsule()).padding(7) }
                        }
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isDefault ? Color.accentColor : .clear, lineWidth: 2))
                        .help(app.name)
                        .accessibilityLabel("使用 \(app.name)\(isDefault ? "，原默认应用" : "")，选择打开方式")
                    }
                }.padding(.horizontal, 22).padding(.bottom, 20)
                if model.candidates.isEmpty {
                    ContentUnavailableView("没有匹配的应用", systemImage: "square.grid.2x2", description: Text("可调整搜索条件，或查看全部应用。"))
                    if model.onlyCompatible { Button("查看全部应用") { model.onlyCompatible = false } }
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
                            }.padding(.horizontal, 10).padding(.vertical, 7)
                        }.buttonStyle(.plain)
                            .background(isDefault ? Color.accentColor.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isDefault ? Color.accentColor : .clear, lineWidth: 2))
                    }
                }.padding(12)
            }.frame(minWidth: 190, idealWidth: 220, maxWidth: 250)
            optionGrid
        }
        .frame(minWidth: 760, minHeight: 360)
    }
    var optionGrid: some View {
        VStack(spacing: 0) {
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 20) {
                    if model.selectedApp == nil {
                        ContentUnavailableView("选择一个应用", systemImage: "square.grid.2x2", description: Text("左侧选择应用后显示可行的打开方式。"))
                            .frame(minWidth: 420, minHeight: 180)
                    }
                    if let app = model.selectedApp, !model.supports(app) { Text("此应用未声明支持全部所选内容，选择下方选项后尝试打开。").font(.callout).foregroundStyle(.secondary) }
                    ForEach(model.optionSections, id: \.self) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section).font(.headline)
                            let columns = model.availableOptions.count == 1 ? [GridItem(.flexible(minimum: 420))] : optionColumns
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                                ForEach(model.availableOptions.filter { $0.section == section }) { option in
                                    let isDefault = model.isOriginalDefault(option)
                                    Button { Task { await model.choose(option) } } label: {
                                        VStack(alignment: .leading, spacing: 10) {
                                            Text(option.title).font(.headline).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                            Text(option.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        }.frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 9)
                                    }
                                    .buttonStyle(.plain)
                                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                                    .overlay(alignment: .topTrailing) {
                                        if isDefault { Text("原默认").font(.caption2).foregroundStyle(.tint).padding(.horizontal, 7).padding(.vertical, 3).background(.thinMaterial, in: Capsule()).padding(7) }
                                    }
                                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(isDefault ? Color.accentColor : Color.primary.opacity(0.10), lineWidth: isDefault ? 2 : 1))
                                    .disabled(model.busy)
                                    .help(option.title + " — " + option.detail)
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
                    ForEach(model.targetErrors.keys.sorted(), id: \.self) { name in Text("\(name)：\(model.targetErrors[name] ?? "")").font(.callout).foregroundStyle(.secondary) }
                }.padding(.horizontal, 22).padding(.bottom, 22)
            }
        }
    }
    var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = model.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if model.busy { ProgressView().controlSize(.small); Text("正在打开…") }
                else { Text(model.queue.isEmpty ? model.status : "另有 \(model.queue.count) 个请求待处理").font(.caption).foregroundStyle(.secondary) }
                if model.step == "apps" { Button("其他应用…") { chooseOtherApp() }.buttonStyle(.link) }
                Spacer()
                Button(model.step == "apps" ? "取消" : "返回应用") { if model.step == "apps" { model.onDismiss?() } else { model.backToApps() } }.keyboardShortcut(.cancelAction).disabled(model.busy)
            }
        }.padding(12)
    }
    func chooseOtherApp() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.application]
        if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier, ![RoutingRules.receiverID, RoutingRules.managerID].contains(id) {
            if !model.apps.contains(where: { $0.id == id }) { model.apps.append(.init(id: id, name: url.deletingPathExtension().lastPathComponent, path: url.path, version: nil, isSystemApp: false, supportedExtensions: [], iconPath: nil)) }
            model.selectApp(id)
        }
    }
}

struct AppTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(configuration.isPressed ? 0.22 : 0.08), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}
