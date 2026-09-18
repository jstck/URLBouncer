// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "URLBouncer",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "URLBouncerCore"
        ),
        .executableTarget(
            name: "URLBouncer",
            dependencies: ["URLBouncerCore"]
        ),
        .testTarget(
            name: "URLBouncerCoreTests",
            dependencies: ["URLBouncerCore"]
        ),
        .testTarget(
            name: "URLBouncerIntegrationTests",
            dependencies: ["URLBouncerCore"]
        ),
    ]
)
