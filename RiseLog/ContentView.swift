import SwiftUI
import RiseKit

/// Skeleton root view. The core workflow UI (issue #4 — jar wall, culture
/// detail, event logging) replaces this; dual-screen adaptation is routed
/// through `FermentWorkspaceLayout` (issue #5).
struct ContentView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Rise Log")
                .font(.title)
                .accessibilityAddTraits(.isHeader)
            Text(RiseKit.milestone)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ContentView()
}
