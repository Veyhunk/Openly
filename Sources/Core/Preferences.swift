import Foundation

@MainActor
enum OpenlyPreferences {
    static let didChange = Notification.Name("Openly.preferencesDidChange")
    private static let defaults: UserDefaults = {
        let shared = UserDefaults(suiteName: "com.openly.app") ?? UserDefaults.standard
        let standard = UserDefaults.standard
        for key in ["Openly.dockIconVisible", "Openly.residentBackground", "Openly.autoOpenSingleOption", "Openly.lightweightDelaySeconds", "Openly.advancedRoutingMode"] where shared.object(forKey: key) == nil {
            if let value = standard.object(forKey: key) { shared.set(value, forKey: key) }
        }
        return shared
    }()

    static var dockIconVisible: Bool {
        get { value("Openly.dockIconVisible", default: true) }
        set { defaults.set(newValue, forKey: "Openly.dockIconVisible"); notify() }
    }
    static var residentBackground: Bool {
        get { value("Openly.residentBackground", default: true) }
        set { defaults.set(newValue, forKey: "Openly.residentBackground"); notify() }
    }
    static var autoOpenSingleOption: Bool {
        get { value("Openly.autoOpenSingleOption", default: true) }
        set { defaults.set(newValue, forKey: "Openly.autoOpenSingleOption"); notify() }
    }
    static var lightweightDelaySeconds: Double {
        get { (defaults.object(forKey: "Openly.lightweightDelaySeconds") as? NSNumber)?.doubleValue ?? 0 }
        set { defaults.set(max(0, newValue), forKey: "Openly.lightweightDelaySeconds"); notify() }
    }
    static var advancedRoutingMode: Bool {
        get { value("Openly.advancedRoutingMode", default: false) }
        set { defaults.set(newValue, forKey: "Openly.advancedRoutingMode"); notify() }
    }
    static var lightweightModeEnabled: Bool { residentBackground }
    static func value(_ key: String, default fallback: Bool) -> Bool {
        _ = defaults.synchronize()
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.bool(forKey: key)
    }
    private static func notify() { NotificationCenter.default.post(name: didChange, object: nil) }
}
