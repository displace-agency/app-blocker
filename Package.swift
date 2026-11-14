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
            dependencies: ["FocusGuardShared", "FocusGuardCore"],
            path: "FocusGuard"
        ),
        .executableTarget(
            name: "FocusGuardDaemon",
            dependencies: ["FocusGuardShared", "FocusGuardCore"],
            path: "FocusGuardDaemon"
        ),
        .target(
            name: "FocusGuardShared",
            path: "FocusGuardShared"
        ),
        // Pure, dependency-free logic (validation, schedule/escalation math,
        // config schema, atomic file IO, app-match rules). Unit-tested.
        .target(
            name: "FocusGuardCore",
            dependencies: ["FocusGuardShared"],
            path: "FocusGuardCore"
        ),
        // Opt-in marketing screenshots of the real SwiftUI views (skipped unless
        // FOCUSGUARD_MARKETING_CAPTURE=1). Uses a demo DaemonClient: no daemon, no /etc.
        .testTarget(
            name: "FocusGuardAppTests",
            dependencies: ["FocusGuard", "FocusGuardShared"],
            path: "Tests/FocusGuardAppTests"
        ),
        .testTarget(
            name: "FocusGuardCoreTests",
            dependencies: ["FocusGuardCore", "FocusGuardShared"],
            path: "Tests/FocusGuardCoreTests"
        ),
    ]
)
