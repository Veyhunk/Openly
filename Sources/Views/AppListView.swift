import SwiftUI

/// App 视图 — 按 App 管理文件关联
struct AppListView: View {

    var viewModel: AppListViewModel

    var body: some View {
        Group {
            switch viewModel.loadingState {
            case .idle:   emptyStateView
            case .loading: loadingView
            case .error(let msg): errorView(msg)
            case .loaded: loadedView
            }
        }
        .task { await viewModel.loadAll() }
    }

    // MARK: - 主视图

    private var loadedView: some View {
        HSplitView {
            appListSidebar.frame(minWidth: 240, idealWidth: 280, maxWidth: 320)
            appDetailView.frame(minWidth: 400)
        }
    }

    // MARK: - App 列表

    private var appListSidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary).font(.callout)
                TextField("搜索 App...", text: viewModel.searchQueryBinding)
                    .textFieldStyle(.plain).font(.body)
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .padding(12)

            Picker("筛选", selection: viewModel.filterTypeBinding) {
                ForEach(AppListViewModel.AppFilterType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12).padding(.bottom, 8)

            Divider()

            List(selection: viewModel.selectedAppIDBinding) {
                ForEach(viewModel.filteredApps) { app in appRow(app).tag(app.id) }
            }
            .listStyle(.plain)

            HStack {
                Text("\(viewModel.filteredApps.count) 个 App")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 8).background(.bar)
        }
    }

    private func appRow(_ app: AppInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: app.isSystemApp ? "apple.logo" : "app.fill")
                .font(.body)
                .foregroundStyle(app.isSystemApp ? Color.secondary : Color.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.body).lineLimit(1)
                Text("\(app.supportedExtensions.count) 个格式")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()

            let count = viewModel.extensionCount(for: app.id)
            if count > 0 {
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - App 详情

    @ViewBuilder
    private var appDetailView: some View {
        if let app = viewModel.selectedApp {
            appExtensionsDetail(app)
        } else {
            noSelectionView
        }
    }

    private var noSelectionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 48)).foregroundStyle(.quaternary)
            Text("选择一个 App").font(.title2).foregroundStyle(.secondary)
            Text("查看该 App 管理的所有文件格式").font(.body).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func appExtensionsDetail(_ app: AppInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: app.isSystemApp ? "apple.logo" : "app.fill")
                        .font(.title)
                        .foregroundStyle(app.isSystemApp ? Color.secondary : Color.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(.title2).fontWeight(.semibold)
                        Text(app.id).font(.caption).foregroundStyle(.secondary).monospaced()
                    }
                }
                Text("管理 \(viewModel.selectedAppAssociations.flatMap { $0.extensions }.count) 个默认关联 / 共支持 \(app.supportedExtensions.count) 个格式")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)

            Divider()

            if viewModel.selectedAppAssociations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 32)).foregroundStyle(.quaternary)
                    Text("此 App 尚未设置任何默认关联")
                        .font(.body).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.selectedAppAssociations) { assoc in
                    HStack {
                        HStack(spacing: 4) {
                            ForEach(assoc.extensions, id: \.self) { ext in
                                Text(".\(ext)")
                                    .font(.body.monospaced())
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                            }
                        }
                        Spacer()
                        Text(assoc.utiIdentifier ?? "")
                            .font(.caption).foregroundStyle(.tertiary).monospaced().lineLimit(1)
                        Spacer()
                        ForEach(assoc.extensions, id: \.self) { ext in
                            Button("移除") {
                                Task {
                                    await viewModel.removeAssociation(extensionID: ext, fromApp: app.id)
                                }
                            }
                            .buttonStyle(.borderless).font(.caption).foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: - 状态

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "app.badge")
                .font(.system(size: 48)).foregroundStyle(.quaternary)
            Text("准备就绪").font(.title2).foregroundStyle(.secondary)
            Button("加载数据") { Task { await viewModel.loadAll() } }
                .buttonStyle(.borderedProminent)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.2)
            Text("正在扫描已安装 App...").foregroundStyle(.secondary)
        }
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40)).foregroundStyle(.yellow)
            Text("加载失败").font(.title3)
            Text(msg).font(.callout).foregroundStyle(.secondary)
            Button("重试") { Task { await viewModel.refresh() } }
                .buttonStyle(.borderedProminent)
        }
    }
}
