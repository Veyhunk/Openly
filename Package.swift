// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Openly", platforms: [.macOS(.v14)], targets: [
    .executableTarget(name: "Openly", path: "Sources", exclude: ["Views", "ViewModels", "App/OpenlyApp.swift", "Services/LaunchServicesReader.swift", "Services/LaunchServicesWriter.swift", "Services/ConfigService.swift"], resources: [.process("Resources")]),
    .executableTarget(name: "OpenlyBridge", path: "BridgeHost")
])
