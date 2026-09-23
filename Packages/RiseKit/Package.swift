// swift-tools-version:6.0
import PackageDescription

// RiseKit — domain + storage core for Rise Log.
// No UI, no networking, no Apple-only frameworks: Linux-testable by design.
//
// Storage: GRDB (SQLite). On Linux, GRDB links the system SQLite via its
// systemLibrary target (apt provider: libsqlite3-dev — installed by the CI
// Linux job before `swift test`). On Apple platforms it links the system
// libsqlite3 shipped with the OS/SDK.
let package = Package(
    name: "RiseKit",
    platforms: [
        .iOS("26.0"),
        .macOS("15.0"),
    ],
    products: [
        .library(name: "RiseKit", targets: ["RiseKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(name: "RiseKit", dependencies: [
            .product(name: "GRDB", package: "GRDB.swift"),
        ]),
        .testTarget(name: "RiseKitTests", dependencies: ["RiseKit"]),
    ]
)
