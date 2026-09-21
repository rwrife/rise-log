// swift-tools-version:6.0
import PackageDescription

// RiseKit — pure-domain core for Rise Log.
// No UI, no networking, no Apple-only frameworks: Linux-testable by design.
let package = Package(
    name: "RiseKit",
    platforms: [
        .iOS("26.0"),
    ],
    products: [
        .library(name: "RiseKit", targets: ["RiseKit"]),
    ],
    targets: [
        .target(name: "RiseKit"),
        .testTarget(name: "RiseKitTests", dependencies: ["RiseKit"]),
    ]
)
