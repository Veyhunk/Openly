import SwiftUI
import AppKit

struct RouteView: View {
    @Bindable var model: RouterModel
    @NativeFocus private var searchFocused: Bool
    private let appColumns = [GridItem(.adaptive(minimum: 112, maximum: 150), spacing: 18)]
    private let optionColumns = [GridItem(.adaptive(minimum: 210, maximum: 320), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.step == "apps" { appGrid } else { optionGrid }
            Divider()
            footer
        }
        .frame(minWidth: 620, minHeight: 420)
        .onAppear { searchFocused = true; PerformanceProbe.visible() }
        .onChange(of: model.focusRequest) { searchFocused = true }
        .onChange(of: model.step) { searchFocused = true }
    }
    var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if model.step == "options" {
                    Button { model.backToApps() } label: { Label("应用", systemImage: "chevron.left") }.disabled(model.busy)
                    if let app = model.selectedApp { AppIcon(path: app.path, size: 28); Text(app.name).font(.title2) }
                } else { Text("选择打开应用").font(.title2) }
                Spacer()
                Text(model.step == "apps" ? "1 / 2" : "2 / 2").font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Text(model.urls.count == 1 ? (model.urls[0].isFileURL ? model.urls[0].lastPathComponent : model.urls[0].host ?? model.urls[0].absoluteString) : "\(model.urls.count) 个项目").lineLimit(1).foregroundStyle(.secondary)
                Spacer()
                if model.step == "options" { Text("点击选项即可打开").font(.callout).foregroundStyle(.secondary) }
            }
            DisclosureGroup("查看完整路径 / 链接") {
                ScrollView { Text(model.urls.map(\.absoluteString).joined(separator: "\n")).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 64)
            }.font(.caption)
        }.padding(20)
    }
    var appGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                TextField("搜索应用", text: $model.search).textFieldStyle(.roundedBorder).focused($searchFocused)
                Picker("显示", selection: $model.onlyCompatible) { Text("支持当前格式").tag(true); Text("全部应用").tag(false) }.pickerStyle(.segmented).frame(width: 230)
            }.padding(.horizontal, 20).padding(.vertical, 14)
            ScrollView {
                LazyVGrid(columns: appColumns, alignment: .center, spacing: 18) {
                    ForEach(model.candidates) { app in
                        Button { model.selectApp(app.id) } label: {
                            VStack(spacing: 9) {
                                AppIcon(path: app.path, size: 54)
                                Text(app.name).font(.callout).multilineTextAlignment(.center).lineLimit(2).frame(height: 34)
                            }.frame(maxWidth: .infinity).padding(.vertical, 12).contentShape(RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(AppTileStyle()).help(app.name).accessibilityLabel("使用 \(app.name)，选择打开方式")
                    }
                }.padding(.horizontal, 22).padding(.bottom, 20)
                if model.candidates.isEmpty {
                    ContentUnavailableView("没有匹配的应用", systemImage: "square.grid.2x2", description: Text("可调整搜索条件，或查看全部应用。"))
                    if model.onlyCompatible { Button("查看全部应用") { model.onlyCompatible = false } }
                }
            }
        }
    }
    var optionGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TextField("搜索打开方式、个人资料或窗口", text: $model.optionSearch).textFieldStyle(.roundedBorder).focused($searchFocused)
                Button { model.refreshWindows(); if model.chromium && model.bridgeIDs[model.selectedAppID ?? ""] != nil { model.loadBrowserTargets() } } label: { Label("刷新", systemImage: "arrow.clockwise") }.disabled(model.busy)
                Spacer(minLength: 12)
                if let option = model.defaultOpenOption, let app = model.selectedApp {
                    Button { Task { await model.choose(option) } } label: {
                        HStack(spacing: 10) {
                            AppIcon(path: app.path, size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("按默认方式打开").font(.headline)
                                Text(app.name).font(.callout)
                                if model.chromium && !option.detail.isEmpty { Text(option.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            }
                        }
                        .frame(minWidth: 210, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy)
                    .help("使用 \(app.name) 的默认打开方式")
                }
            }.padding(.horizontal, 20).padding(.vertical, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let app = model.selectedApp, !model.supports(app) { Text("此应用未声明支持全部所选内容，选择下方选项后尝试打开。").font(.callout).foregroundStyle(.secondary) }
                    ForEach(model.optionSections, id: \.self) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section).font(.headline)
                            LazyVGrid(columns: optionColumns, alignment: .leading, spacing: 12) {
                                ForEach(model.availableOptions.filter { $0.section == section }) { option in
                                    Button { Task { await model.choose(option) } } label: {
                                        VStack(alignment: .leading, spacing: 10) {
                                            Image(systemName: option.symbol).font(.title3).foregroundStyle(.tint)
                                            Text(option.title).font(.headline).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                            Text(option.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        }.frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading).padding(12)
                                    }.buttonStyle(AppTileStyle()).disabled(model.busy).help(option.title + " — " + option.detail)
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
