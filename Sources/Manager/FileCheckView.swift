import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CheckedFile: Identifiable {
    var id: String { url.path }
    let url: URL
    var hasOverride: Bool
    var status: String
}
struct FileCheckView: View {
    @NativeState private var files: [CheckedFile] = []
    @NativeState private var selected = Set<String>()
    @NativeState private var confirm = false
    @NativeState private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("检查文件").font(.title2); Spacer(); Button("选择文件…") { choose() } }
            Text("检查文件是否单独指定了打开应用。拖入文件或使用选择按钮。").foregroundStyle(.secondary)
            Table(files, selection: $selected) {
                TableColumn("文件") { f in Text(f.url.lastPathComponent).help(f.url.path) }
                TableColumn("检查结果", value: \.status)
                TableColumn("路径") { f in Text(f.url.deletingLastPathComponent().path).textSelection(.enabled) }
            }.overlay { if files.isEmpty { ContentUnavailableView("选择打开方式异常的文件", systemImage: "doc.text.magnifyingglass") } }
            HStack {
                Text("已检查 \(files.count) 个文件").foregroundStyle(.secondary); Spacer()
                Button("重新检查") { inspect(files.map(\.url)) }.disabled(files.isEmpty || busy)
                Button("移除所选文件的单独设置…") { confirm = true }.disabled(!files.contains { selected.contains($0.id) && $0.hasOverride } || busy)
            }
        }.padding(24)
        .dropDestination(for: URL.self) { urls, _ in inspect(urls); return true }
        .confirmationDialog("移除所选文件的单独打开设置？完成后使用文件类型的默认规则。", isPresented: $confirm) {
            Button("移除设置") {
                for i in files.indices where selected.contains(files[i].id) && files[i].hasOverride {
                    if removexattr(files[i].id, "com.apple.LaunchServices.OpenWith", 0) == 0 {
                        files[i] = check(files[i].url)
                    } else { files[i].status = "移除失败：" + String(cString: strerror(errno)) }
                }
            }
            Button("取消", role: .cancel) {}
        }
    }
    func choose() { let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; if panel.runModal() == .OK { inspect(panel.urls) } }
    func inspect(_ urls: [URL]) {
        for url in urls where url.isFileURL {
            let row = check(url)
            if let i = files.firstIndex(where: { $0.id == row.id }) { files[i] = row } else { files.append(row) }
        }
    }
    func check(_ url: URL) -> CheckedFile {
        let count = getxattr(url.path, "com.apple.LaunchServices.OpenWith", nil, 0, 0, 0)
        let error = errno
        return CheckedFile(url: url, hasOverride: count >= 0, status: count >= 0 ? "有单独设置" : error == ENOATTR ? "无单独设置" : "无法读取：" + String(cString: strerror(error)))
    }
}
