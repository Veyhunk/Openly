import SwiftUI
import Observation

/// 扩展名视图 — 玻璃材质，毛玻璃工具栏 + 清爽表格
struct ExtensionListView: View {

    @Bindable var viewModel: ExtensionListViewModel

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
        .sheet(isPresented: $viewModel.showBatchPanel) {
            BatchOperationView(selectedExtensions: Array(viewModel.selectedExtensions), viewModel: viewModel)
                .frame(width: 520, height: 520)
        }
        .sheet(isPresented: $viewModel.showAppPicker) { appPickerSheet }
    }

    // MARK: - 主视图

    private var loadedView: some View {
        VStack(spacing: 0) {
            toolbarView
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)

            Divider()

            Table(viewModel.filteredExtensions, selection: $viewModel.selectedExtensions) {
                TableColumn("扩展名") { ext in extensionNameCell(ext) }
                    .width(min: 110, ideal: 130)
                TableColumn("描述") { ext in
                    Text(ext.description ?? "—")
                        .foregroundStyle(ext.description != nil ? .primary : .tertiary)
                }
                .width(min: 180, ideal: 240)
                TableColumn("分类") { ext in
                    if let c = ext.category { categoryBadge(c) }
                    else { Text("—").foregroundStyle(.tertiary) }
                }
                .width(min: 72, ideal: 84)
                TableColumn("默认打开方式") { ext in defaultAppCell(ext) }
                    .width(min: 160, ideal: 200)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))

            statusBarView
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(.bar)
        }
    }

    // MARK: - 工具栏

    private var toolbarView: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索扩展名、描述或 App…", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 7))

            Picker("分类", selection: $viewModel.selectedCategory) {
                Text("全部分类").tag(nil as String?)
                ForEach(viewModel.availableCategories, id: \.self) { cat in
                    Text(cat).tag(cat as String?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 110)

            Picker("筛选", selection: $viewModel.filterType) {
                ForEach(ExtensionListViewModel.FilterType.allCases) { t in Text(t.rawValue).tag(t) }
            }
            .pickerStyle(.segmented)

            Spacer()

            if !viewModel.selectedExtensions.isEmpty {
                Button { viewModel.showBatchPanel = true } label: {
                    Label("批量操作 (\(viewModel.selectedExtensions.count))", systemImage: "rectangle.stack.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Button { Task { await viewModel.refresh() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("刷新 (⌘R)")
        }
    }

    // MARK: - 单元格

    private func extensionNameCell(_ ext: ExtensionInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: fileIcon(for: ext.id))
                .font(.title3)
                .foregroundStyle(fileColor(for: ext))
                .frame(width: 24)
            Text(".\(ext.id)")
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }

    private func categoryBadge(_ category: String) -> some View {
        Text(category)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }

    private func defaultAppCell(_ ext: ExtensionInfo) -> some View {
        HStack(spacing: 6) {
            if let name = ext.defaultAppName {
                HStack(spacing: 4) {
                    if ext.isSystemApp {
                        Image(systemName: "apple.logo").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(name).lineLimit(1)
                }
            } else {
                Text("未关联").foregroundStyle(.tertiary)
            }
            Spacer()
            Button { viewModel.selectedExtForChange = ext; viewModel.showAppPicker = true } label: {
                Image(systemName: "chevron.down.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("更换默认 App")
        }
    }

    // MARK: - 底栏

    private var statusBarView: some View {
        HStack(spacing: 8) {
            Text("\(viewModel.filteredExtensions.count) 个扩展名")
                .font(.caption).foregroundStyle(.secondary)
            if !viewModel.selectedExtensions.isEmpty {
                Text("·").foregroundStyle(.quaternary)
                Text("已选 \(viewModel.selectedExtensions.count) 项")
                    .font(.caption).foregroundStyle(.blue)
            }
            Spacer()
        }
    }

    // MARK: - App 选择器 Sheet

    private var appPickerSheet: some View {
        NavigationStack {
            List {
                if let ext = viewModel.selectedExtForChange {
                    Section {
                        if ext.allAvailableApps.isEmpty {
                            HStack {
                                Image(systemName: "app.dashed").foregroundStyle(.secondary)
                                Text("未找到能打开此格式的 App").foregroundStyle(.secondary)
                            }
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
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(app.name)
                                        Text(app.id).font(.caption2).foregroundStyle(.secondary).monospaced()
                                    }
                                    Spacer()
                                    if app.id == ext.defaultAppBundleID {
                                        Image(systemName: "checkmark").foregroundStyle(.blue).fontWeight(.semibold)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("为 .\(ext.id) 选择默认 App")
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
            .listStyle(.inset)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { viewModel.showAppPicker = false; viewModel.selectedExtForChange = nil }
                }
            }
        }
        .frame(width: 440, height: 500)
    }

    // MARK: - 状态

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48)).foregroundStyle(.quaternary)
            VStack(spacing: 6) {
                Text("文件打开方式管理").font(.title2).fontWeight(.medium)
                Text("管理文件扩展名与 App 的关联").foregroundStyle(.secondary)
            }
            Button("加载数据") { Task { await viewModel.loadAll() } }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.windowBackground)
    }

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView().scaleEffect(1.2).controlSize(.small)
            Text("正在扫描文件关联…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.windowBackground)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40)).foregroundStyle(.orange)
            VStack(spacing: 6) {
                Text("加载失败").font(.title3)
                Text(msg).font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 320)
            }
            Button("重试") { Task { await viewModel.refresh() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.windowBackground)
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
