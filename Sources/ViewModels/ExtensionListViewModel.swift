import Foundation
import SwiftUI
import Observation

/// 扩展名列表视图的 ViewModel
@MainActor
@Observable
final class ExtensionListViewModel {

    // MARK: - 状态

    enum LoadingState: Equatable {
        case idle, loading, loaded
        case error(String)
    }

    var loadingState: LoadingState = .idle
    var searchQuery: String = ""
    var selectedCategory: String? = nil
    var filterType: FilterType = .all
    var selectedExtensions: Set<String> = []
    var isBatchMode: Bool = false
    var showBatchPanel: Bool = false
    var showAppPicker: Bool = false
    var selectedExtForChange: ExtensionInfo? = nil

    enum FilterType: String, CaseIterable, Identifiable {
        case all = "全部"
        case system = "系统 App"
        case thirdParty = "第三方 App"
        case unassigned = "未关联"
        var id: String { rawValue }
    }

    private(set) var allExtensions: [ExtensionInfo] = []
    private(set) var categories: [String] = []

    private let reader = LaunchServicesReader()
    private let writer = LaunchServicesWriter()
    private let scanner = AppScanner()
    private let descDB = ExtensionDescriptionDB()

    // MARK: - 计算

    var filteredExtensions: [ExtensionInfo] {
        var result = allExtensions
        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            result = result.filter { ext in
                ext.id.lowercased().contains(query) ||
                (ext.description?.lowercased().contains(query) ?? false) ||
                (ext.defaultAppName?.lowercased().contains(query) ?? false)
            }
        }
        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }
        switch filterType {
        case .all: break
        case .system: result = result.filter { $0.isSystemApp }
        case .thirdParty: result = result.filter { !$0.isSystemApp && $0.defaultAppBundleID != nil }
        case .unassigned: result = result.filter { $0.defaultAppBundleID == nil }
        }
        return result
    }

    var availableCategories: [String] {
        Array(Set(allExtensions.compactMap { $0.category })).sorted()
    }

    var isAllSelected: Bool {
        !filteredExtensions.isEmpty && selectedExtensions.count == filteredExtensions.count
    }

    // MARK: - 绑定辅助（避免 @Bindable 宏依赖）

    var searchQueryBinding: Binding<String> {
        Binding(get: { self.searchQuery }, set: { self.searchQuery = $0 })
    }
    var selectedCategoryBinding: Binding<String?> {
        Binding(get: { self.selectedCategory }, set: { self.selectedCategory = $0 })
    }
    var filterTypeBinding: Binding<FilterType> {
        Binding(get: { self.filterType }, set: { self.filterType = $0 })
    }
    var selectedExtensionsBinding: Binding<Set<String>> {
        Binding(get: { self.selectedExtensions }, set: { self.selectedExtensions = $0 })
    }
    var showBatchPanelBinding: Binding<Bool> {
        Binding(get: { self.showBatchPanel }, set: { self.showBatchPanel = $0 })
    }
    var showAppPickerBinding: Binding<Bool> {
        Binding(get: { self.showAppPicker }, set: { self.showAppPicker = $0 })
    }

    // MARK: - 方法

    func loadAll() async {
        loadingState = .loading
        do {
            async let associations = reader.readAllAssociations()
            async let apps = scanner.scanAllApps()

            let (loadedAssociations, loadedApps) = try await (associations, apps)

            let uniqExts = Array(Set(loadedAssociations.flatMap { $0.extensions }))
            let descInfos = await descDB.batchInfo(for: uniqExts)
            let descLookup: [String: (desc: String?, category: String?)] = Dictionary(
                descInfos.map { ($0.ext, ($0.desc, $0.category)) },
                uniquingKeysWith: { first, _ in first }
            )

            var allExts: [ExtensionInfo] = []
            for assoc in loadedAssociations {
                for ext in assoc.extensions {
                    let (desc, cat) = descLookup[ext] ?? (nil, nil)
                    let availableApps = loadedApps.filter { $0.supportedExtensions.contains(ext) }
                    allExts.append(ExtensionInfo(
                        id: ext, utiIdentifier: assoc.utiIdentifier,
                        description: desc, category: cat,
                        defaultAppBundleID: assoc.defaultAppBundleID,
                        defaultAppName: assoc.defaultAppName,
                        defaultAppPath: assoc.defaultAppPath,
                        isSystemApp: assoc.isSystemApp,
                        allAvailableApps: availableApps
                    ))
                }
            }

            var seen: [String: ExtensionInfo] = [:]
            for ext in allExts {
                if let existing = seen[ext.id] {
                    if existing.defaultAppBundleID != nil { continue }
                    if ext.defaultAppBundleID != nil { seen[ext.id] = ext }
                } else {
                    seen[ext.id] = ext
                }
            }

            // 补充描述库中有但 LSHandlers 中没有的扩展名
            let allDescInfo = await descDB.allExtensionsInfo()
            for (extName, desc, cat) in allDescInfo {
                guard seen[extName] == nil else { continue }
                let availableApps = loadedApps.filter { $0.supportedExtensions.contains(extName) }
                seen[extName] = ExtensionInfo(
                    id: extName, utiIdentifier: nil,
                    description: desc, category: cat,
                    defaultAppBundleID: nil, defaultAppName: nil, defaultAppPath: nil,
                    isSystemApp: false,
                    allAvailableApps: availableApps
                )
            }

            self.allExtensions = Array(seen.values).sorted { $0.id < $1.id }
            self.categories = availableCategories
            self.loadingState = .loaded
        } catch {
            self.loadingState = .error(error.localizedDescription)
        }
    }

    func refresh() async { await loadAll() }

    func setDefaultApp(for extensionID: String, bundleID: String) async {
        do {
            try await writer.setDefaultApp(forExtension: extensionID, bundleID: bundleID)
            await refresh()
        } catch {
            print("[Openly] setDefaultApp failed: \(error)")
        }
    }

    func clearAssociation(for extensionID: String) async {
        do {
            try await writer.clearAssociation(forExtension: extensionID)
            await refresh()
        } catch {
            print("[Openly] clearAssociation failed: \(error)")
        }
    }

    func batchSetDefaultApp(extensions: [String], bundleID: String) async -> [(String, Bool)] {
        let results = await writer.setDefaultAppBatch(extensions: extensions, bundleID: bundleID)
        await refresh()
        return results.map { ($0.ext, $0.success) }
    }

    func toggleSelectAll() {
        if isAllSelected { selectedExtensions.removeAll() }
        else { selectedExtensions = Set(filteredExtensions.map { $0.id }) }
    }

    func exitBatchMode() {
        isBatchMode = false
        selectedExtensions.removeAll()
    }
}
