import Foundation
import Observation

/// App 列表视图的 ViewModel
@MainActor
@Observable
final class AppListViewModel {

    enum LoadingState: Equatable {
        case idle, loading, loaded
        case error(String)
    }

    var loadingState: LoadingState = .idle
    var searchQuery: String = ""
    var filterType: AppFilterType = .all
    var selectedAppID: String? = nil

    enum AppFilterType: String, CaseIterable, Identifiable {
        case all = "全部", system = "系统 App", thirdParty = "第三方 App"
        var id: String { rawValue }
    }

    private(set) var allApps: [AppInfo] = []
    private(set) var appAssociations: [String: [FileAssociation]] = [:]

    private let reader = LaunchServicesReader()
    private let writer = LaunchServicesWriter()
    private let scanner = AppScanner()

    // MARK: - 计算

    var filteredApps: [AppInfo] {
        var result = allApps
        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            result = result.filter { $0.name.lowercased().contains(q) || $0.id.lowercased().contains(q) }
        }
        switch filterType {
        case .all: break
        case .system: result = result.filter { $0.isSystemApp }
        case .thirdParty: result = result.filter { !$0.isSystemApp }
        }
        return result
    }

    var selectedAppAssociations: [FileAssociation] {
        guard let id = selectedAppID else { return [] }
        return appAssociations[id] ?? []
    }

    var selectedApp: AppInfo? {
        guard let id = selectedAppID else { return nil }
        return allApps.first { $0.id == id }
    }

    // MARK: - 方法

    func loadAll() async {
        loadingState = .loading
        do {
            async let apps = scanner.scanAllApps()
            async let associations = reader.readAllAssociations()
            let (loadedApps, loadedAssociations) = try await (apps, associations)

            var map: [String: [FileAssociation]] = [:]
            for app in loadedApps {
                let appAssocs = loadedAssociations.filter { $0.defaultAppBundleID == app.id }
                if !appAssocs.isEmpty { map[app.id] = appAssocs }
            }

            self.allApps = loadedApps
            self.appAssociations = map
            self.allAssociations = loadedAssociations
            self.loadingState = .loaded
        } catch {
            self.loadingState = .error(error.localizedDescription)
        }
    }

    func refresh() async { await loadAll() }

    func removeAssociation(extensionID: String, fromApp bundleID: String) async {
        do {
            try await writer.clearAssociation(forExtension: extensionID)
            await refresh()
        } catch {
            print("[Openly] removeAssociation failed: \(error)")
        }
    }

    func addAssociation(extensionID: String, toApp bundleID: String) async {
        do {
            try await writer.setDefaultApp(forExtension: extensionID, bundleID: bundleID)
            await refresh()
        } catch {
            print("[Openly] addAssociation failed: \(error)")
        }
    }

    func extensionCount(for bundleID: String) -> Int {
        appAssociations[bundleID]?.reduce(0) { $0 + $1.extensions.count } ?? 0
    }

    /// 查询某个扩展名当前由哪个 App 作为默认打开
    func currentDefaultForExtension(_ ext: String) -> (bundleID: String, name: String)? {
        for (_, associations) in appAssociations {
            for assoc in associations {
                if assoc.extensions.contains(ext), let bundleID = assoc.defaultAppBundleID {
                    return (bundleID, assoc.defaultAppName ?? bundleID)
                }
            }
        }
        return nil
    }

    /// 所有 LaunchServices 关联（不按 Bundle ID 分组），用于全局查找
    private(set) var allAssociations: [FileAssociation] = []

    /// 检查某扩展名当前是否由指定 App 设为默认
    func isDefaultForExtension(_ ext: String, bundleID: String) -> Bool {
        for assoc in allAssociations {
            if assoc.extensions.contains(ext), assoc.defaultAppBundleID == bundleID {
                return true
            }
        }
        return false
    }
}
