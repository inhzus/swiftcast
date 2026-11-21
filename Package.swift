// swift-tools-version: 6.2
import PackageDescription

// Features are plugins: each is a target that depends only on SwiftCastPluginKit, and the app
// lists them in `PluginRegistry`. A plugin can't see the app or another plugin.
let package = Package(
    name: "SwiftCast",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "SwiftCastPluginKit"),
        .target(name: "AppsPlugin", dependencies: ["SwiftCastPluginKit"]),
        .target(name: "CalculatorPlugin", dependencies: ["SwiftCastPluginKit"]),
        .target(name: "SwiftCastCore"),
        .executableTarget(name: "SwiftCast", dependencies: [
            "SwiftCastCore", "SwiftCastPluginKit", "AppsPlugin", "CalculatorPlugin",
        ]),
        .testTarget(name: "SwiftCastCoreTests", dependencies: ["SwiftCastCore"]),
        .testTarget(name: "AppsPluginTests", dependencies: ["AppsPlugin", "SwiftCastPluginKit"]),
        .testTarget(name: "CalculatorPluginTests", dependencies: ["CalculatorPlugin", "SwiftCastPluginKit"]),
    ]
)
