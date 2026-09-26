import SwiftUI

/// The skeleton `ContentView` was replaced by the core workflow UI in
/// issue #4. Issue #5 routes the app through `FermentWorkspaceLayout`, the
/// sole jar-wall/detail composition and future dual-screen adaptation seam.
/// This file intentionally holds only the preview shim.
#Preview {
    FermentWorkspaceLayout()
        .environment(try! AppEnvironment())
}
