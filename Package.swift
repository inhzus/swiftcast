// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftCast",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SwiftCastCore"),
        .executableTarget(name: "SwiftCast", dependencies: ["SwiftCastCore"]),
        .testTarget(name: "SwiftCastCoreTests", dependencies: ["SwiftCastCore"]),
    ]
)
