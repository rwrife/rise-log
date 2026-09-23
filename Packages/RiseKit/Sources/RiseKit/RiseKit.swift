/// RiseKit — pure-domain core for Rise Log.
///
/// Namespace marker for the domain + storage layers.
///
/// Issue #2 landed the domain entities (`Culture`, `Event`, `LineageGraph`)
/// and the deterministic derivation engine (`StatusEngine`). Issue #3 landed
/// the GRDB store (`RiseLogStore`: migration v1, append-only event table,
/// indexed derived queries) — still zero-network, SQLite-only.
public enum RiseKit {
    /// Namespace marker for the domain layer.
    public static let domain = "RiseKit"

    /// Current build/CI milestone marker consumed by the app's debug surface.
    public static let milestone = "M2-store"
}
