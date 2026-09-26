import Foundation

// MARK: - Workspace routing (issue #5 — the single dual-screen seam)
//
// iPhone Duo (wall as a persistent control surface beside a detail pane) is
// a DOCUMENTED DESIGN TARGET, not a supported configuration. There is no
// released SDK API for fold/hinge/span state, and this codebase must never
// reference unreleased hardware APIs. All layout routing therefore funnels
// through exactly one pure decision point: `FermentWorkspaceRouting.route`.
//
// The SwiftUI `FermentWorkspaceLayout` view in the app target observes the
// environment's horizontal size class, converts it to a `WorkspaceBand`, and
// calls `route(band:)` — it contains NO routing logic of its own. A Linux
// test (`FermentWorkspaceRoutingTests`) proves the truth table, and a
// source-scan test proves the size class (and jar-wall/detail composition)
// is consulted nowhere else in app sources.

/// Coarse size-class band fed into the routing seam. The app maps
/// `horizontalSizeClass == .compact` to `.compact` and anything regular to
/// `.spanned`; nothing else may classify a workspace.
public enum WorkspaceBand: String, Codable, Sendable, CaseIterable {
    case compact
    case spanned
}

/// The presentation the seam selects for the current band.
public enum WorkspacePresentation: Equatable, Sendable {
    /// Single NavigationStack: jar wall pushes to culture detail. Today's
    /// (and every current-iPhone) shipped behavior.
    case singleColumn
    /// Persistent jar-wall control surface beside a detail pane — the
    /// spanned hook point for the future iPhone Duo target. Reachable ONLY
    /// when `spannedSupportEnabled` is explicitly flipped on; no shipping
    /// build does that today.
    case twoPane
}

/// The single routing decision point for Rise Log's workspace layout.
public enum FermentWorkspaceRouting {
    /// Master gate for the spanned/two-pane workspace. `false` is the
    /// shipped state: even a regular-size environment keeps the
    /// single-column layout (the app is iPhone-only, `TARGETED_DEVICE_FAMILY
    /// = 1`, so this only matters if a future OS ever reports regular width
    /// on iPhone hardware, e.g. a Duo unfold). Flipping this to `true` is
    /// the documented hook for the iPhone Duo two-pane workspace and must
    /// come with real hardware evidence before it ever lands (never claimed
    /// as tested otherwise) — see docs/dual-screen.md.
    public static let spannedSupportEnabled: Bool = false

    /// Pure routing truth table:
    /// - `.compact`                      → `.singleColumn` (always)
    /// - `.spanned`, gate off (shipped)  → `.singleColumn` (hook point, inert)
    /// - `.spanned`, gate on (future)    → `.twoPane`
    public static func route(
        band: WorkspaceBand,
        spannedSupportEnabled: Bool = spannedSupportEnabled
    ) -> WorkspacePresentation {
        switch band {
        case .compact:
            return .singleColumn
        case .spanned:
            return spannedSupportEnabled ? .twoPane : .singleColumn
        }
    }
}
