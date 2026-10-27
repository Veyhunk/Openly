import Foundation
import AppKit
import UniformTypeIdentifiers

@MainActor enum SystemChecks {
    static func run() async throws {
        let fm = FileManager.default
        let folder = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(".build/checks/System-" + UUID().uuidString)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let fixture = folder.appendingPathComponent("Original.app")
        let typeID = "com.openly.validation." + UUID().uuidString.lowercased()
        let ext = "openlyprobe" + String(UUID().uuidString.prefix(8)).lowercased()
        let appID = typeID + ".app"
        let contents = fixture.appendingPathComponent("Contents")
        try fm.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try fm.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: contents.appendingPathComponent("MacOS/Probe"))
        let plist: [String: Any] = ["CFBundleIdentifier": appID, "CFBundleName": "Openly Test Original", "CFBundleExecutable": "Probe", "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "LSMinimumSystemVersion": "14.0", "CFBundleSupportedPlatforms": ["MacOSX"], "CFBundleDocumentTypes": [["CFBundleTypeName": "Openly Probe", "CFBundleTypeRole": "Viewer", "LSHandlerRank": "Owner", "LSItemContentTypes": [typeID]]], "UTExportedTypeDeclarations": [["UTTypeIdentifier": typeID, "UTTypeConformsTo": ["public.data"], "UTTypeTagSpecification": ["public.filename-extension": [ext]]]]]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        let sign = Process(); sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign"); sign.arguments = ["--force", "--sign", "-", fixture.path]; try sign.run(); sign.waitUntilExit()
        guard LSRegisterURL(fixture as CFURL, true) == noErr else { throw OpenlyError("测试应用注册失败") }
        let receiver = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/Openly.app/Contents/Helpers/Openly Receiver.app")
        guard LSRegisterURL(receiver as CFURL, true) == noErr else { throw OpenlyError("接收器注册失败") }
        setenv("OPENLY_STATE_DIR", folder.appendingPathComponent("state").path, 1)
        defer {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
            process.arguments = ["-u", fixture.path]; try? process.run(); process.waitUntilExit()
            unsetenv("OPENLY_STATE_DIR")
            try? fm.removeItem(at: folder)
        }
        guard let type = UTType(typeID) else { throw OpenlyError("测试类型未解析") }
        try await NSWorkspace.shared.setDefaultApplication(at: fixture, toOpen: type)
        for _ in 0..<10 where AssociationService.current(typeID) != appID { try await Task.sleep(for: .milliseconds(100)) }
        guard AssociationService.current(typeID) == appID else { throw OpenlyError("原始应用设置未生效：current=\(AssociationService.current(typeID) ?? "nil"), url=\(String(describing: NSWorkspace.shared.urlForApplication(toOpen: type))), apps=\(NSWorkspace.shared.urlsForApplications(toOpen: type)), registered=\(String(describing: NSWorkspace.shared.urlForApplication(withBundleIdentifier: appID)))") }
        if CommandLine.arguments.contains("--legacy-probe") {
            let target = folder.appendingPathComponent("Target.app")
            try fm.copyItem(at: fixture, to: target)
            var targetInfo = plist
            let targetID = appID + ".target"
            targetInfo["CFBundleIdentifier"] = targetID
            targetInfo["CFBundleDocumentTypes"] = [["CFBundleTypeName": "Probe", "CFBundleTypeRole": "Viewer", "LSHandlerRank": "Alternate", "LSItemContentTypes": [typeID]]]
            try PropertyListSerialization.data(fromPropertyList: targetInfo, format: .xml, options: 0).write(to: target.appendingPathComponent("Contents/Info.plist"))
            let signing = Process(); signing.executableURL = URL(fileURLWithPath: "/usr/bin/codesign"); signing.arguments = ["--force", "--sign", "-", target.path]; try signing.run(); signing.waitUntilExit()
            LSRegisterURL(target as CFURL, true)
            let status = LSSetDefaultRoleHandlerForContentType(typeID as CFString, .all, targetID as CFString)
            try await Task.sleep(for: .seconds(2))
            print("LEGACY status=\(status), expected=\(targetID), current=\(AssociationService.current(typeID) ?? "nil"), legacyRead=\(LSCopyDefaultRoleHandlerForContentType(typeID as CFString, .all)?.takeRetainedValue() as String? ?? "nil")")
            let unregister = Process(); unregister.executableURL = URL(fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"); unregister.arguments = ["-u", target.path]; try unregister.run(); unregister.waitUntilExit()
            return
        }
        let store = AppStore()
        store.prepare([ext], target: RoutingRules.receiverID)
        guard store.plan.count == 1, store.plan[0].id == typeID else { throw OpenlyError("测试类型预览不正确") }
        await store.execute()
        guard AssociationService.current(typeID) == RoutingRules.receiverID else { throw OpenlyError("接管核验失败：\(store.results)") }
        guard let record = store.state.records.first(where: { $0.id == typeID }), record.previousAppID == appID, record.targetAppID == RoutingRules.batchReceiverID else { throw OpenlyError("批量接管记录不匹配：expected=\(appID), records=\(store.state.records), plan=\(store.plan), results=\(store.results)") }
        store.prepareRestore([record]); await store.execute()
        guard AssociationService.current(typeID) == appID, !store.state.records.contains(where: { $0.id == typeID }) else { throw OpenlyError("恢复核验失败") }
        print("PASS: isolated system UTI takeover, persisted recovery and restoration")

        let file = folder.appendingPathComponent("check.txt"); try Data("test".utf8).write(to: file)
        let key = "com.apple.LaunchServices.OpenWith"
        let data = Data("probe".utf8)
        let written = data.withUnsafeBytes { setxattr(file.path, key, $0.baseAddress, data.count, 0, 0) }
        guard written == 0, getxattr(file.path, key, nil, 0, 0, 0) > 0, removexattr(file.path, key, 0) == 0, getxattr(file.path, key, nil, 0, 0, 0) == -1, errno == ENOATTR else { throw OpenlyError("文件覆盖检测或清理失败") }
        print("PASS: file override detection and removal")
    }
}
