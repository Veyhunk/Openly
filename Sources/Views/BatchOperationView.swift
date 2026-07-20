import SwiftUI

/// 批量操作面板 — 将多个扩展名统一分配到一个 App
/// 状态由父 ViewModel 驱动
struct BatchOperationView: View {

    let selectedExtensions: [String]
    var viewModel: ExtensionListViewModel

    private let scanner = AppScanner()

    // 用临时存储（编译期会被内联为计算属性）
    private var availableApps: [AppInfo] {
        get async {
            await scanner.scanAllApps()
        }
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BatchOperationContent(
            selectedExtensions: selectedExtensions,
            viewModel: viewModel,
            dismiss: dismiss
        )
    }
}

/// 内部实现 —— 隔离状态管理
private struct BatchOperationContent: View {

    let selectedExtensions: [String]
    var viewModel: ExtensionListViewModel
    let dismiss: DismissAction

    // Local mutable state via Observable helper
    private class BatchState: ObservableObject {
        var searchQuery = ""
        var selectedBundleID: String? = nil
        var availableApps: [AppInfo] = []
        var isApplying = false
        var results: [(String, Bool)] = []
        var isLoaded = false
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 加载中
                // 使用简化视图 — 选择 + 提交
                BatchSelectionView(
                    selectedExtensions: selectedExtensions,
                    viewModel: viewModel,
                    dismiss: dismiss
                )
            }
            .navigationTitle("批量操作")
        }
    }
}

/// 批量操作的选择视图
private struct BatchSelectionView: View {

    let selectedExtensions: [String]
    var viewModel: ExtensionListViewModel
    let dismiss: DismissAction

    private let scanner = AppScanner()
    private var availableApps: [AppInfo] {
        get async { await scanner.scanAllApps() }
    }

    var body: some View {
        PlaceholderBatchView(
            extensions: selectedExtensions,
            onApply: { bundleID in
                let _ = await viewModel.batchSetDefaultApp(
                    extensions: selectedExtensions,
                    bundleID: bundleID
                )
                dismiss()
            }
        )
    }
}

/// 简化批量操作占位视图
private struct PlaceholderBatchView: View {

    let extensions: [String]
    let onApply: (String) async -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("已选 \(extensions.count) 个扩展名")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(extensions, id: \.self) { ext in
                            Text(".\(ext)")
                                .font(.caption.monospaced())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }
            .padding(16)
            .background(.bar)

            Divider()

            Spacer()

            Text("请先在扩展名列表中选择一个目标 App，然后点击批量操作按钮。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(32)

            Spacer()

            Divider()

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.borderless)
            }
            .padding(12)
        }
    }
}
