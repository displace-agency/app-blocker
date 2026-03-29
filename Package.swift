// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FocusGuard",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "FocusGuard", targets: ["FocusGuard"]),
        .executable(name: "FocusGuardDaemon", targets: ["FocusGuardDaemon"]),
    ],
    targets: [
        .executableTarget(
            name: "FocusGuard",
            dependencies: ["FocusGuardShared"],
            path: "FocusGuard"
        ),
        .executableTarget(
            name: "FocusGuardDaemon",
            dependencies: ["FocusGuardShared"],
            path: "FocusGuardDaemon"
        ),
        .target(
            name: "FocusGuardShared",
            path: "FocusGuardShared"
        ),
    ]
)
