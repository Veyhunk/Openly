import Foundation

@MainActor final class RoutingTests {
    func testNormalizationAndInvalidTypes() {
        XCTAssertEqual(RoutingRules.normalize(" .PDF \n"), "pdf")
        XCTAssertNil(RoutingRules.typeID("../foo"))
        XCTAssertNil(RoutingRules.typeID("*"))
    }
    func testAliasesAreOneWriteAndKeepScope() {
        let plan = RoutingRules.plan(["jpg", ".JPEG", "jpg"], target: "example.app") { _ in "old.app" }
        XCTAssertEqual(plan.count, 1)
        XCTAssertTrue(plan[0].extensions.contains("jpg"))
        XCTAssertTrue(plan[0].extensions.contains("jpeg"))
        XCTAssertEqual(plan[0].previousAppID, "old.app")
    }
    func testRecoveryPreservesExternalChanges() {
        let record = AssociationRecord(id: "public.text", extensions: ["txt"], previousAppID: "old", targetAppID: "openly")
        XCTAssertEqual(RoutingRules.recoveryTarget(record: record, current: "openly"), "old")
        XCTAssertEqual(RoutingRules.recoveryTarget(record: record, current: "new"), "new")
        XCTAssertNil(RoutingRules.recoveryTarget(record: record, current: nil))
    }
    func testVersionedImportAndLegacyCompatibility() throws {
        let legacy = Data(#"{"version":"1.0","exportDate":"2026-01-01","associations":[{"extensions":["pdf"],"bundleID":"example"}]}"#.utf8)
        let config = try JSONDecoder().decode(BackupConfig.self, from: legacy)
        XCTAssertNoThrow(try RoutingRules.validate(config))
        XCTAssertNil(config.associations[0].takeover)
        var future = config; future.version = "99.0"
        XCTAssertThrowsError(try RoutingRules.validate(future))
    }
    func testSnapshotRoundTrip() throws {
        var value = LocalState()
        value.records = [.init(id: "scheme:https", extensions: [], previousAppID: "browser", targetAppID: RoutingRules.receiverID)]
        let copy = try JSONDecoder().decode(LocalState.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(copy.records[0].previousAppID, "browser")
    }
    func testTemporaryBrowserArgumentsDoNotReusePersonalProfile() {
        let url = URL(string: "https://example.com/a?q=hello%20world")!
        let args = BrowserService.arguments(profile: "Profile 2", mode: "temporary", urls: [url], temporaryDirectory: URL(fileURLWithPath: "/tmp/Openly-test"))
        XCTAssertEqual(args, ["--user-data-dir=/tmp/Openly-test", "--new-window", url.absoluteString])
        XCTAssertFalse(args.contains { $0.hasPrefix("--profile-directory") })
    }
    func testBrowserArgumentsKeepURLAsSingleArgument() {
        let url = URL(string: "https://example.com/?q=%24%28touch%20bad%29")!
        let args = BrowserService.arguments(profile: "Profile 1", mode: "incognito", urls: [url])
        XCTAssertEqual(args.count, 3)
        XCTAssertEqual(args.last, url.absoluteString)
        XCTAssertTrue(args.contains("--incognito"))
    }
    @MainActor func testExtensionIDValidation() {
        XCTAssertTrue(BrowserBridge.validExtensionID(String(repeating: "a", count: 32)))
        XCTAssertFalse(BrowserBridge.validExtensionID("../bad"))
        XCTAssertFalse(BrowserBridge.validExtensionID(String(repeating: "z", count: 32)))
    }
    func testAppGridDefaultsToSupportedApps() {
        let model = RouterModel()
        model.urls = [URL(fileURLWithPath: "/tmp/sample.txt")]
        model.apps = [
            .init(id: "supported", name: "Text", path: "/tmp/Text.app", version: nil, isSystemApp: false, supportedExtensions: ["txt"], iconPath: nil, supportedSchemes: []),
            .init(id: "other", name: "Other", path: "/tmp/Other.app", version: nil, isSystemApp: false, supportedExtensions: ["pdf"], iconPath: nil, supportedSchemes: [])
        ]
        model.updateCompatibility()
        XCTAssertEqual(model.candidates.map(\.id), ["supported"])
        model.onlyCompatible = false
        XCTAssertEqual(model.candidates.count, 2)
        let advancedMode = OpenlyPreferences.advancedRoutingMode
        OpenlyPreferences.advancedRoutingMode = false
        defer { OpenlyPreferences.advancedRoutingMode = advancedMode }
        model.selectApp("supported")
        XCTAssertEqual(model.step, "options")
        model.backToApps()
        XCTAssertEqual(model.step, "apps")
        XCTAssertEqual(model.urls[0].lastPathComponent, "sample.txt")
    }
    func testBrowserCardsEnumerateProfilesWindowsAndGroups() {
        let model = RouterModel()
        model.apps = [.init(id: "com.google.Chrome", name: "Chrome", path: "/tmp/Chrome.app", version: nil, isSystemApp: false, supportedExtensions: [], iconPath: nil, supportedSchemes: ["https"])]
        model.selectedAppID = "com.google.Chrome"
        model.profiles = [.init(id: "Default", name: "Personal"), .init(id: "Profile 1", name: "Work")]
        model.browserSnapshots["Profile 1"] = .init(windows: [.init(id: 10, title: "Project", incognito: false, count: 3)], groups: [.init(id: 20, windowId: 10, title: "References", color: "blue")])
        let options = model.availableOptions
        XCTAssertEqual(options.count, 9)
        XCTAssertEqual(Set(options.map(\.id)).count, options.count)
        XCTAssertEqual(options.filter { $0.mode == "temporary" }.count, 1)
        let group = options.first { $0.groupID == 20 }!
        XCTAssertEqual(group.profile, "Profile 1")
        XCTAssertEqual(group.browserWindowID, 10)
        model.optionSearch = "References"
        XCTAssertEqual(model.availableOptions.count, 1)
    }
    func testCorruptStateIsPreserved() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Openly-corrupt-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        setenv("OPENLY_STATE_DIR", folder.path, 1)
        defer { unsetenv("OPENLY_STATE_DIR"); try? FileManager.default.removeItem(at: folder) }
        let original = Data("invalid-json".utf8)
        try original.write(to: folder.appendingPathComponent("state.json"))
        let store = AppStore()
        XCTAssertTrue(store.error != nil)
        store.persist()
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("state.json")), original)
    }
    @MainActor func testQueueNeverChangesConfirmedRequest() {
        let model = RouterModel()
        model.urls = [URL(fileURLWithPath: "/tmp/first.txt")]
        model.enqueue([URL(fileURLWithPath: "/tmp/second.txt")])
        XCTAssertEqual(model.urls[0].lastPathComponent, "first.txt")
        XCTAssertEqual(model.queue.count, 1)
        XCTAssertTrue(model.next())
        XCTAssertEqual(model.urls[0].lastPathComponent, "second.txt")
        XCTAssertFalse(model.next())
    }
}

func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { precondition(a == b, "Expected \(a) == \(b)", file: (file), line: line) }
func XCTAssertTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { precondition(value, "Expected true", file: (file), line: line) }
func XCTAssertFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { precondition(!value, "Expected false", file: (file), line: line) }
func XCTAssertNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { precondition(value == nil, "Expected nil", file: (file), line: line) }
func XCTAssertNoThrow(_ expression: @autoclosure () throws -> Void) { do { try expression() } catch { fatalError("Unexpected error: \(error)") } }
func XCTAssertThrowsError(_ expression: @autoclosure () throws -> Void) { do { try expression(); fatalError("Expected error") } catch {} }

@main struct TestMain {
    @MainActor static func main() async throws {
        if CommandLine.arguments.contains("--integration") || CommandLine.arguments.contains("--legacy-probe") { try await SystemChecks.run(); return }
        let tests = RoutingTests()
        tests.testNormalizationAndInvalidTypes()
        tests.testAliasesAreOneWriteAndKeepScope()
        tests.testRecoveryPreservesExternalChanges()
        try tests.testVersionedImportAndLegacyCompatibility()
        try tests.testSnapshotRoundTrip()
        tests.testTemporaryBrowserArgumentsDoNotReusePersonalProfile()
        tests.testBrowserArgumentsKeepURLAsSingleArgument()
        tests.testExtensionIDValidation()
        tests.testQueueNeverChangesConfirmedRequest()
        try tests.testCorruptStateIsPreserved()
        tests.testAppGridDefaultsToSupportedApps()
        tests.testBrowserCardsEnumerateProfilesWindowsAndGroups()
        print("PASS: 12 routing, recovery, import, isolation and queue checks")
    }
}
