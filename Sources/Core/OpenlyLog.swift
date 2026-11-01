import OSLog

enum OpenlyLog {
    static let windows = Logger(subsystem: "com.openly.app", category: "windows")
    static let browser = Logger(subsystem: "com.openly.app", category: "browser")
    static let lifecycle = Logger(subsystem: "com.openly.app", category: "lifecycle")
}
