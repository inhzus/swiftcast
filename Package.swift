// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftCast",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "SwiftCastCore"),
        .executableTarget(name: "SwiftCast", dependencies: ["SwiftCastCore"]),
        .testTarget(name: "SwiftCastCoreTests", dependencies: ["SwiftCastCore"]),
    ]
)
