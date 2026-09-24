import SwiftUI

/// The skeleton `ContentView` was replaced by the core workflow UI in
/// issue #4. The root view now lives in `JarWallView.swift` as `RootView`
/// (NavigationStack + jar wall + create sheet); this file intentionally
/// holds only the preview shim so the file history stays clear.
#Preview {
    RootView()
        .environment(try! AppEnvironment())
}
