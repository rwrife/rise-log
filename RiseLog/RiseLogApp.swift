import SwiftUI
import RiseKit

/// App entry point (issue #4): boots the durable store environment and
/// roots the jar-wall → detail workflow.
///
/// iPhone-only by user directive 2026-09-15 (`TARGETED_DEVICE_FAMILY = 1`
/// in every build configuration; CI enforces it pre- and post-build).
/// Zero-network by construction: no network APIs anywhere in app or
/// package sources — CI enforces an empty-allowlist scan.
@main
struct RiseLogApp: App {
    /// Booted once at process start; injected down the view tree.
    @State private var env = AppEnvironment.bootstrap()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
        }
    }
}
