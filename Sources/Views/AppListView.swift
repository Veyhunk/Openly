import SwiftUI
import AppKit
import Observation

/// App 视图 — 玻璃侧栏 + 毛玻璃内容区
struct AppListView: View {

    @Bindable var viewModel: AppListViewModel

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
    }

    // MARK: - 主视图

    private var loadedView: some View {
        HStack(spacing: 0) {
            appListSidebar
                .frame(width: 260)
                .background(.ultraThinMaterial)

            Rectangle()
                .frame(width: 1)
                .foregroundStyle(.quaternary)

            appDetailView
        }
    }

    // MARK: - 侧栏

    private var appListSidebar: some View {
        VStack(spacing: 0) {
            // 搜索
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索 App…", text: $viewModel.searchQuery).textFieldStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 7))
            .padding(12)

            // 筛选
            Picker("筛选", selection: $viewModel.filterType) {
                ForEach(AppListViewModel.AppFilterType.allCases) { t in Text(t.rawValue).tag(t) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            // App 列表
            List(selection: $viewModel.selectedAppID) {
                ForEach(viewModel.filteredApps) { app in appRow(app).tag(app.id) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            // 底栏
            HStack {
                Text("\(viewModel.filteredApps.count) 个 App").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.bar)
        }
    }

    private func appRow(_ app: AppInfo) -> some View {
        HStack(spacing: 8) {
            if let iconPath = app.iconPath, let nsImage = NSImage(contentsOfFile: iconPath) {
                Image(nsImage: nsImage).resizable().frame(width: 22, height: 22)
            } else {
                Image(systemName: app.isSystemApp ? "apple.logo" : "app.fill")
                    .font(.body).frame(width: 22)
                    .foregroundStyle(app.isSystemApp ? Color.secondary : Color.blue)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).lineLimit(1)
                Text("\(app.supportedExtensions.count) 种格式").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    // MARK: - 详情

    @ViewBuilder
    private var appDetailView: some View {
        if let app = viewModel.selectedApp {
            appExtensionsDetail(app)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 48)).foregroundStyle(.quaternary)
                VStack(spacing: 4) {
                    Text("选择一个 App").font(.title2).fontWeight(.medium)
                    Text("查看该 App 管理的所有文件格式").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.windowBackground)
        }
    }

    private func appExtensionsDetail(_ app: AppInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 头部
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Group {
                        if let ip = app.iconPath, let img = NSImage(contentsOfFile: ip) {
                            Image(nsImage: img).resizable()
                        } else {
                            Image(systemName: app.isSystemApp ? "apple.logo" : "app.fill")
                                .font(.title2)
                                .foregroundStyle(app.isSystemApp ? Color.secondary : Color.blue)
                        }
                    }
                    .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(.title3).fontWeight(.semibold)
                        Text(app.id).font(.caption).foregroundStyle(.secondary).monospaced()
                    }
                }

                HStack(spacing: 20) {
                    if let v = app.version { metaLabel("版本", v) }
                    metaLabel("支持格式", "\(app.supportedExtensions.count) 个")
                    let managed = viewModel.selectedAppAssociations.flatMap { $0.extensions }.count
                    if managed > 0 { metaLabel("默认打开", "\(managed) 个") }
                }

                Text(app.path).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            .padding(24)

            Divider()

            // 扩展名列表 — 展示所有受支持的扩展名
            if app.supportedExtensions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "questionmark.app.dashed").font(.system(size: 28)).foregroundStyle(.quaternary)
                    Text("该 App 未声明任何文件格式支持").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(app.supportedExtensions, id: \.self) { ext in
                        extensionManageRow(ext, app: app)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .background(.windowBackground)
    }

    /// 单个扩展名的管理行
    private func extensionManageRow(_ ext: String, app: AppInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: fileIcon(for: ext))
                .font(.body)
                .foregroundStyle(fileColor(for: ext))
                .frame(width: 20)

            Text(".\(ext)")
                .font(.body.monospaced()).fontWeight(.medium)

            Spacer()

            if viewModel.isDefaultForExtension(ext, bundleID: app.id) {
                // 当前 App 是默认
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
                Text("默认").font(.caption).foregroundStyle(.secondary)

                Button {
                    Task { await viewModel.removeAssociation(extensionID: ext, fromApp: app.id) }
                } label: {
                    Text("移除").font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
            } else if let current = viewModel.currentDefaultForExtension(ext) {
                // 其他 App 是默认
                Text(current.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Button {
                    Task { await viewModel.addAssociation(extensionID: ext, toApp: app.id) }
                } label: {
                    Text("切换").font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.blue)
            } else {
                // 无默认 App
                Text("未关联").font(.caption).foregroundStyle(.tertiary)

                Button {
                    Task { await viewModel.addAssociation(extensionID: ext, toApp: app.id) }
                } label: {
                    Text("设为默认").font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - 状态视图

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "app.badge").font(.system(size: 48)).foregroundStyle(.quaternary)
            VStack(spacing: 6) {
                Text("已安装 App").font(.title2).fontWeight(.medium)
                Text("查看每个 App 支持的文件格式").foregroundStyle(.secondary)
            }
            Button("加载数据") { Task { await viewModel.loadAll() } }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.windowBackground)
    }

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView().scaleEffect(1.2)
            Text("正在扫描已安装 App…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.windowBackground)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 40)).foregroundStyle(.orange)
            Text("加载失败").font(.title3)
            Text(msg).font(.callout).foregroundStyle(.secondary).frame(maxWidth: 300)
            Button("重试") { Task { await viewModel.refresh() } }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.windowBackground)
    }

    private func metaLabel(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.tertiary)
            Text(value).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - 图标辅助

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

    private func fileColor(for ext: String) -> Color {
        // Match common extension categories — approximate color mapping
        let imageExts = Set(["jpg","jpeg","png","gif","bmp","webp","heic","heif","svg","psd","raw","tiff","tif","ico","icns"])
        let videoExts = Set(["mp4","mov","avi","mkv","webm"])
        let audioExts = Set(["mp3","wav","aac","flac","ogg","m4a"])
        let docExts  = Set(["pdf","doc","docx","xls","xlsx","ppt","pptx","pages","numbers","key","epub"])
        let codeExts = Set(["swift","c","cpp","py","js","ts","go","rs","java","rb","sh"])
        let webExts  = Set(["html","htm","css","xml","json","yaml","toml"])
        let archiveExts = Set(["zip","rar","7z","tar","gz","dmg","iso","pkg"])
        if imageExts.contains(ext)   { return .blue }
        if videoExts.contains(ext)   { return .purple }
        if audioExts.contains(ext)   { return .pink }
        if docExts.contains(ext)     { return .orange }
        if codeExts.contains(ext)    { return .green }
        if webExts.contains(ext)     { return .cyan }
        if archiveExts.contains(ext) { return .brown }
        return .secondary
    }
}
