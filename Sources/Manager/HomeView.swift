import SwiftUI

struct HomeView: View {
    @Bindable var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("欢迎使用 Openly").font(.title)
                    Text("Openly 接收文件和链接，在打开前让你选择应用、浏览器个人资料、窗口或标签组。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                receiverCard
                GroupBox("常用入口") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("文件类型、应用和打开接管分别管理默认打开方式与每次打开时的选择。")
                        HStack {
                            Button("打开接管") { store.page = "打开接管" }
                            Button("权限设置") { store.page = "权限设置" }
                            Button("偏好设置") { store.page = "偏好设置" }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .navigationTitle("首页")
        .task { await store.ensureReceiverRunning() }
    }

    var receiverCard: some View {
        GroupBox("后台接管 Receiver") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: store.receiverStatus.symbol)
                        .foregroundStyle(store.receiverStatus == .running ? .green : .secondary)
                    Text(store.receiverStatus.label).font(.headline)
                    Spacer()
                    if store.receiverBusy { ProgressView().controlSize(.small) }
                }
                Text("Receiver 负责接收系统传来的文件和链接。主程序关闭后是否保留它，仍按当前的后台行为设置和关闭时选择执行。")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("启动") { Task { await store.startReceiver() } }
                        .disabled(store.receiverBusy || store.receiverStatus == .running)
                    Button("重启") { Task { await store.restartReceiver() } }
                        .disabled(store.receiverBusy)
                    Button("停止") { Task { await store.stopReceiver() } }
                        .disabled(store.receiverBusy || store.receiverStatus != .running)
                    Spacer()
                    Button("刷新状态") { store.refreshReceiverStatus() }
                        .buttonStyle(.link)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
