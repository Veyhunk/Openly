import SwiftUI
import AppKit

/// App 视图 — 玻璃侧栏 + 毛玻璃内容区
struct AppListView: View {

    var viewModel: AppListViewModel

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
                TextField("搜索 App…", text: viewModel.searchQueryBinding).textFieldStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 7))
            .padding(12)

            // 筛选
            Picker("筛选", selection: viewModel.filterTypeBinding) {
                ForEach(AppListViewModel.AppFilterType.allCases) { t in Text(t.rawValue).tag(t) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            // App 列表
            List(selection: viewModel.selectedAppIDBinding) {
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

            // 扩展名列表
            if viewModel.selectedAppAssociations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "link").font(.system(size: 28)).foregroundStyle(.quaternary)
                    Text("尚未设置任何默认关联").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.selectedAppAssociations) { assoc in
                    HStack {
                        HStack(spacing: 4) {
                            ForEach(assoc.extensions, id: \.self) { ext in
                                Text(".\(ext)")
                                    .font(.body.monospaced()).fontWeight(.medium)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        Spacer()
                        Text(assoc.utiIdentifier ?? "").font(.caption2).foregroundStyle(.tertiary).monospaced()
                        Spacer()
                        ForEach(assoc.extensions, id: \.self) { ext in
                            Button("移除") {
                                Task { await viewModel.removeAssociation(extensionID: ext, fromApp: app.id) }
                            }
                            .buttonStyle(.borderless).font(.caption).foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
            }
        }
        .background(.windowBackground)
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
}
