import SwiftUI
import AppKit

struct RouteView: View {
    @Bindable var model: RouterModel
    @NativeFocus private var searchFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("用哪个应用打开？").font(.title2)
                Text(model.urls.count == 1 ? (model.urls[0].isFileURL ? model.urls[0].lastPathComponent : model.urls[0].host ?? model.urls[0].absoluteString) : "\(model.urls.count) 个项目").foregroundStyle(.secondary)
                DisclosureGroup("查看完整路径 / 链接") { ScrollView { Text(model.urls.map(\.absoluteString).joined(separator: "\n")).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 70) }
            }.padding(20)
            Divider()
            HSplitView {
                VStack {
                    TextField("搜索应用", text: $model.search).textFieldStyle(.roundedBorder).focused($searchFocused).padding(10)
                    List(model.candidates, selection: $model.selectedAppID) { app in
                        HStack { AppIcon(path: app.path); VStack(alignment: .leading) { Text(app.name); if !model.supports(app) { Text("支持情况待确认").font(.caption).foregroundStyle(.secondary) } } }.tag(app.id)
                    }
                    Button("其他应用…") {
                        let panel = NSOpenPanel(); panel.allowedContentTypes = [.application]
                        if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier, ![RoutingRules.receiverID, RoutingRules.managerID].contains(id) {
                            if !model.apps.contains(where: { $0.id == id }) { model.apps.append(.init(id: id, name: url.deletingPathExtension().lastPathComponent, path: url.path, version: nil, isSystemApp: false, supportedExtensions: [], iconPath: nil)) }
                            model.selectedAppID = id
                        }
                    }.padding(8)
                }.frame(minWidth: 190, idealWidth: 220, maxWidth: 260)
                ScrollView {
                    if let app = model.selectedApp {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack { AppIcon(path: app.path, size: 32); Text(app.name).font(.title3) }
                            if model.chromium && model.mode != "temporary" {
                                Picker("个人资料", selection: $model.profile) { ForEach(model.profiles) { Text($0.name).tag($0.id) } }
                            }
                            Picker("打开位置", selection: $model.mode) {
                                Text(model.vscode ? "最近活动窗口" : "默认打开").tag("default")
                                if model.chromium || model.vscode || model.genericNewWindow { Text("新窗口").tag("new") }
                                if model.chromium { Text("新无痕窗口").tag("incognito"); Text("新建临时会话").tag("temporary") }
                                if !model.windows.isEmpty { Text(model.vscode ? "指定窗口" : "指定窗口（兼容打开）").tag("window") }
                                if model.chromium && model.bridgeIDs[app.id] != nil { Text("浏览器窗口 / 标签组").tag("browserWindow") }
                            }.pickerStyle(.radioGroup)
                            if model.mode == "temporary" { Text("使用全新的临时用户数据目录启动浏览器。").foregroundStyle(.secondary) }
                            if model.mode == "window" {
                                Picker("窗口", selection: $model.windowID) {
                                    Text("选择窗口").tag(nil as Int?)
                                    ForEach(model.windows) { Text($0.title).tag(Optional($0.id)) }
                                }
                                Text(model.vscode ? "先切换到所选窗口，再打开文件。" : "兼容打开：应用可能自行决定打开位置。").font(.callout).foregroundStyle(.secondary)
                            }
                            if model.mode == "browserWindow" { browserTargets }
                            if !WindowAccess.trusted { Button("授权后选择已有窗口") { WindowAccess.openSettings() } }
                            else { Button("刷新应用窗口") { model.refreshWindows() } }
                            if model.chromium && model.bridgeIDs[app.id] == nil { Text("窗口与标签组：请在 Openly 的打开接管页连接浏览器扩展。").font(.callout).foregroundStyle(.secondary) }
                            if !model.supports(app) { Toggle("仍使用此应用打开", isOn: $model.allowUnsupported) }
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    } else { ContentUnavailableView("选择一个应用", systemImage: "arrow.up.forward.app", description: Text("按需选择个人资料、窗口或新会话")) }
                }.frame(minWidth: 350)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if let error = model.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                HStack {
                    if model.busy || model.loadingTargets { ProgressView().controlSize(.small) }
                    Text(model.queue.isEmpty ? model.status : "另有 \(model.queue.count) 个请求待处理").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("取消") { model.onDismiss?() }.keyboardShortcut(.cancelAction).disabled(model.busy)
                    Button("打开") { Task { await model.openSelected() } }.keyboardShortcut(.defaultAction).disabled(!model.canOpen)
                }
            }.padding(16)
        }
        .frame(minWidth: 660, minHeight: 440)
        .onAppear { searchFocused = true; PerformanceProbe.visible() }
        .onChange(of: model.focusRequest) { searchFocused = true }
        .onChange(of: model.selectedAppID) { model.appChanged() }
        .onChange(of: model.profile) { model.profileChanged() }
        .onChange(of: model.browserWindowID) { model.groupID = nil }
    }
    var browserTargets: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button("读取浏览器窗口与分组") { model.loadBrowserTargets() }.disabled(model.loadingTargets)
            Picker("窗口", selection: $model.browserWindowID) {
                Text("选择窗口").tag(nil as Int?)
                ForEach(model.snapshot.windows) { Text("\($0.title) · \($0.count) 标签\($0.incognito ? " · 无痕" : "")").tag(Optional($0.id)) }
            }
            Picker("标签组", selection: $model.groupID) {
                Text("普通标签页").tag(nil as Int?)
                ForEach(model.snapshot.groups.filter { $0.windowId == model.browserWindowID }) { Text("\($0.title) · \($0.color)").tag(Optional($0.id)) }
            }
        }
    }
}
