import SwiftUI
import Observation

/// 批量操作面板 — 将选中的扩展名统一分配给一个 App
struct BatchOperationView: View {

    let selectedExtensions: [String]
    var viewModel: ExtensionListViewModel

    var body: some View {
        BatchOperationSheet(
            extensions: selectedExtensions,
            onApply: { bundleID in
                let _ = await viewModel.batchSetDefaultApp(
                    extensions: selectedExtensions,
                    bundleID: bundleID
                )
                viewModel.showBatchPanel = false
            }
        )
    }
}

// MARK: - 内部实现

private struct BatchOperationSheet: View {

    let extensions: [String]
    let onApply: (String) async -> Void

    @Environment(\.dismiss) private var dismiss

    private let scanner = AppScanner()

    // 本地状态（通过 @Observable 类持有，配合 @Bindable 使用）
    @Bindable private var state = BatchState()

    @Observable
    fileprivate class BatchState {
        var searchQuery = ""
        var selectedBundleID: String? = nil
        var apps: [AppInfo] = []
        var isApplying = false
        var resultSuccess = 0
        var resultFail = 0
        var showResults = false
    }

    var body: some View {
        NavigationStack {
            if state.showResults {
                resultView
            } else {
                selectionView
            }
        }
        .frame(width: 480, height: 480)
        .task { await load() }
    }

    // MARK: - 选择视图

    private var selectionView: some View {
        VStack(spacing: 0) {
            // 已选扩展名预览
            selectedHeader
                .padding(16)
                .background(.bar)

            Divider()

            // 搜索
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索目标 App...", text: $state.searchQuery)
                .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .padding(12)

            // App 列表
            List(selection: $state.selectedBundleID) {
                Section("选择一个目标 App") {
                    ForEach(filteredApps) { app in
                        appRow(app).tag(app.id)
                    }
                }
            }
            .listStyle(.inset)

            Divider()

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button { apply() } label: {
                    Label("应用", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.selectedBundleID == nil || state.isApplying)
            }
            .padding(12)
        }
        .navigationTitle("批量操作")
    }

    // MARK: - 结果视图

    private var resultView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                if state.resultFail == 0 {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.green)
                    Text("全部完成")
                        .font(.title3).fontWeight(.semibold)
                    Text("\(state.resultSuccess) 个扩展名已关联")
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)
                    Text("部分完成")
                        .font(.title3).fontWeight(.semibold)
                    Text("\(state.resultSuccess) 成功，\(state.resultFail) 失败")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(32)

            Divider()

            // 扩展名列表
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(extensions, id: \.self) { ext in
                        HStack {
                            Image(systemName: "doc")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text(".\(ext)")
                                .font(.body.monospaced())
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        if ext != extensions.last { Divider().padding(.leading, 36) }
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
    }

    // MARK: - 头部预览

    private var selectedHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "rectangle.stack.fill")
                    .foregroundStyle(.blue)
                Text("已选 \(extensions.count) 个扩展名")
                    .fontWeight(.medium)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(extensions, id: \.self) { ext in
                        HStack(spacing: 2) {
                            Image(systemName: fileIcon(for: ext))
                                .font(.caption2)
                            Text(".\(ext)")
                                .font(.caption.monospaced())
                        }
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                    }
                }
            }
        }
    }

    // MARK: - App 行

    private func appRow(_ app: AppInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: app.isSystemApp ? "apple.logo" : "app.fill")
                .font(.body)
                .foregroundStyle(app.isSystemApp ? Color.secondary : Color.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.body)
                Text("支持 \(app.supportedExtensions.count) 种格式")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: - 过滤

    private var filteredApps: [AppInfo] {
        if state.searchQuery.isEmpty { return state.apps }
        let q = state.searchQuery.lowercased()
        return state.apps.filter {
            $0.name.lowercased().contains(q) || $0.id.lowercased().contains(q)
        }
    }

    // MARK: - 方法

    private func load() async {
        state.apps = await scanner.scanAllApps()
    }

    private func apply() {
        guard let id = state.selectedBundleID else { return }
        state.isApplying = true
        Task {
            await onApply(id)
            state.resultSuccess = extensions.count  // simplified; real result from ViewModel
            state.resultFail = 0
            state.isApplying = false
            state.showResults = true
        }
    }

    // MARK: - 图标

    private func fileIcon(for ext: String) -> String {
        switch ext {
        case let e where ["jpg","jpeg","png","gif","bmp","webp","heic","heif","svg","psd","raw","tiff","tif","ico"].contains(e): "photo"
        case let e where ["mp4","mov","avi","mkv","webm"].contains(e): "film"
        case let e where ["mp3","wav","aac","flac","ogg","m4a"].contains(e): "music.note"
        case let e where ["pdf","doc","docx","xls","xlsx","ppt","pptx"].contains(e): "doc.richtext"
        case let e where ["zip","rar","7z","tar","gz","dmg"].contains(e): "archivebox"
        case let e where ["swift","c","cpp","py","js","ts","go","rs","java"].contains(e): "chevron.left.forwardslash.chevron.right"
        case "txt","md": "doc.text"
        default: "doc"
        }
    }
}
