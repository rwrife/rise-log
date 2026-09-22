/// RiseKit — pure-domain core for Rise Log.
///
/// Namespace marker for the domain layer.
///
/// Issue #2 landed the domain entities (`Culture`, `Event`, `LineageGraph`)
/// and the deterministic derivation engine (`StatusEngine`) here. The GRDB
/// store is issue #3 and lives in the app target, not this package.
public enum RiseKit {
    /// Namespace marker for the domain layer.
    public static let domain = "RiseKit"

    /// Current build/CI milestone marker consumed by the app's debug surface.
    public static let milestone = "M1-domain"
}
