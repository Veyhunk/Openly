import SwiftUI

/// 扩展名视图 — 按后缀管理文件关联
struct ExtensionListView: View {

    var viewModel: ExtensionListViewModel

    var body: some View {
        Group {
            switch viewModel.loadingState {
            case .idle:                    emptyStateView
            case .loading:                 loadingView
            case .error(let msg):          errorView(msg)
            case .loaded:                  loadedView
            }
        }
        .task { await viewModel.loadAll() }
        .sheet(isPresented: viewModel.showBatchPanelBinding) {
            BatchOperationView(
                selectedExtensions: Array(viewModel.selectedExtensions),
                viewModel: viewModel
            )
            .frame(width: 480, height: 400)
        }
        .sheet(isPresented: viewModel.showAppPickerBinding) {
            appPickerSheet
        }
    }

    // MARK: - 主视图

    private var loadedView: some View {
        VStack(spacing: 0) {
            toolbarView.padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            Table(viewModel.filteredExtensions, selection: viewModel.selectedExtensionsBinding) {
                TableColumn("扩展名") { ext in extensionNameCell(ext) }.width(min: 100, ideal: 120)
                TableColumn("描述") { ext in
                    Text(ext.description ?? "—")
                        .foregroundStyle(ext.description != nil ? .primary : .tertiary)
                }.width(min: 160, ideal: 220)
                TableColumn("分类") { ext in
                    if let c = ext.category { categoryBadge(c) }
                    else { Text("—").foregroundStyle(.tertiary) }
                }.width(min: 72, ideal: 80)
                TableColumn("默认 App") { ext in defaultAppCell(ext) }.width(min: 140, ideal: 180)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            statusBarView.padding(.horizontal, 16).padding(.vertical, 8).background(.bar)
        }
    }

    // MARK: - 工具栏

    private var toolbarView: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.callout)
                TextField("搜索扩展名、描述或 App...", text: viewModel.searchQueryBinding)
                    .textFieldStyle(.plain).font(.body)
            }
            .padding(6).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            Picker("分类", selection: viewModel.selectedCategoryBinding) {
                Text("全部分类").tag(nil as String?)
                ForEach(viewModel.availableCategories, id: \.self) { cat in Text(cat).tag(cat as String?) }
            }
            .pickerStyle(.menu).frame(width: 120)

            Picker("筛选", selection: viewModel.filterTypeBinding) {
                ForEach(ExtensionListViewModel.FilterType.allCases) { type in Text(type.rawValue).tag(type) }
            }
            .pickerStyle(.segmented).frame(width: 240)

            Spacer()

            if !viewModel.selectedExtensions.isEmpty {
                Button { viewModel.showBatchPanel = true } label: {
                    Label("批量操作 (\(viewModel.selectedExtensions.count))", systemImage: "rectangle.stack")
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
            }

            Button { Task { await viewModel.refresh() } } label: {
                Image(systemName: "arrow.clockwise").font(.callout)
            }
            .buttonStyle(.borderless).help("刷新")
        }
    }

    // MARK: - 表格

    private func extensionNameCell(_ ext: ExtensionInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: fileIcon(for: ext.id)).font(.title3)
                .foregroundStyle(fileColor(for: ext)).frame(width: 24)
            Text(".\(ext.id)").font(.body).fontWeight(.medium).monospaced()
        }
    }

    private func categoryBadge(_ category: String) -> some View {
        Text(category).font(.caption).padding(.horizontal, 8).padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }

    private func defaultAppCell(_ ext: ExtensionInfo) -> some View {
        HStack(spacing: 6) {
            if let n = ext.defaultAppName {
                if ext.isSystemApp { Label(n, systemImage: "apple.logo").font(.body) }
                else { Text(n).font(.body) }
            } else { Text("未关联").foregroundStyle(.tertiary) }
            Spacer()
            Button { viewModel.selectedExtForChange = ext; viewModel.showAppPicker = true } label: {
                Image(systemName: "chevron.down.circle").font(.callout).foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless).help("更换默认 App")
        }
    }

    // MARK: - 底栏

    private var statusBarView: some View {
        HStack {
            Text("共 \(viewModel.filteredExtensions.count) 个扩展名").font(.caption).foregroundStyle(.secondary)
            Spacer()
            if !viewModel.selectedExtensions.isEmpty {
                Text("已选 \(viewModel.selectedExtensions.count) 项").font(.caption).foregroundStyle(.blue)
            }
        }
    }

    // MARK: - 选择器 Sheet

    private var appPickerSheet: some View {
        NavigationStack {
            List {
                if let ext = viewModel.selectedExtForChange {
                    Section("为 .\(ext.id) 选择默认 App") {
                        if ext.allAvailableApps.isEmpty {
                            Text("未找到能打开此格式的 App").foregroundStyle(.secondary)
                        }
                        ForEach(ext.allAvailableApps) { app in
                            Button {
                                Task {
                                    await viewModel.setDefaultApp(for: ext.id, bundleID: app.id)
                                    viewModel.showAppPicker = false
                                    viewModel.selectedExtForChange = nil
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: app.isSystemApp ? "apple.logo" : "app.fill")
                                        .foregroundStyle(app.isSystemApp ? Color.secondary : Color.blue)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(app.name).font(.body)
                                        Text(app.id).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if app.id == ext.defaultAppBundleID {
                                        Image(systemName: "checkmark").foregroundStyle(.blue).fontWeight(.semibold)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if ext.defaultAppBundleID != nil {
                        Section {
                            Button(role: .destructive) {
                                Task {
                                    await viewModel.clearAssociation(for: ext.id)
                                    viewModel.showAppPicker = false
                                    viewModel.selectedExtForChange = nil
                                }
                            } label: { Label("清除关联", systemImage: "trash") }
                        }
                    }
                }
            }
            .listStyle(.inset).navigationTitle("选择默认 App")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { viewModel.showAppPicker = false; viewModel.selectedExtForChange = nil }
                }
            }
        }
        .frame(width: 420, height: 480)
    }

    // MARK: - 状态

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 48)).foregroundStyle(.quaternary)
            Text("准备就绪").font(.title2).foregroundStyle(.secondary)
            Button("加载数据") { Task { await viewModel.loadAll() } }.buttonStyle(.borderedProminent)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.2)
            Text("正在扫描文件关联...").foregroundStyle(.secondary)
        }
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 40)).foregroundStyle(.yellow)
            Text("加载失败").font(.title3)
            Text(msg).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 300)
            Button("重试") { Task { await viewModel.refresh() } }.buttonStyle(.borderedProminent)
        }
    }

    // MARK: - 图标

    private func fileIcon(for ext: String) -> String {
        switch ext {
        case let e where ["jpg","jpeg","png","gif","bmp","webp","heic","heif","svg","psd","raw","tiff","tif","ico","icns"].contains(e): "photo"
        case let e where ["mp4","mov","avi","mkv","webm"].contains(e): "film"
        case let e where ["mp3","wav","aac","flac","ogg","m4a"].contains(e): "music.note"
        case let e where ["pdf","doc","docx","xls","xlsx","ppt","pptx","pages","numbers","key","epub"].contains(e): "doc.richtext"
        case let e where ["zip","rar","7z","tar","gz","dmg","iso","pkg"].contains(e): "archivebox"
        case let e where ["swift","c","cpp","py","js","ts","go","rs","java","rb","sh"].contains(e): "chevron.left.forwardslash.chevron.right"
        case let e where ["html","htm","css","xml","json","yaml","toml"].contains(e): "curlybraces"
        case "txt","md","rtf","csv","log": "doc.text"
        default: "doc"
        }
    }

    private func fileColor(for ext: ExtensionInfo) -> Color {
        switch ext.category {
        case "图像": .blue; case "视频": .purple; case "音频": .pink
        case "文档": .orange; case "代码": .green; case "压缩": .brown
        case "网页": .cyan; case "字体": .indigo
        default: .secondary
        }
    }
}
