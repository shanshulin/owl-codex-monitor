// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OwlCodexMonitor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "OwlCodexMonitor", targets: ["OwlCodexMonitor"])
    ],
    targets: [
        .executableTarget(name: "OwlCodexMonitor")
    ]
)
