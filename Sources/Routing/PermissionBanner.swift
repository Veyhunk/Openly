import SwiftUI

struct PermissionBanner: View {
    let permissions: [OpenlyPermissionKind]

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.trianglebadge.exclamationmark").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 5) {
                    Text("缺少权限：" + permissions.map(\.title).joined(separator: "、")).font(.headline)
                    Text(permissions.map(\.purpose).joined(separator: " ")).font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("打开 Openly 权限设置") { OpenlyPermissionService.openManagerPermissionPage() }
                            .buttonStyle(.link)
                        Text("授权后重新打开此选择窗口").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
