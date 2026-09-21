/// RiseKit — pure-domain core for Rise Log.
///
/// Issue #1 ships only the skeleton namespace so CI has a real, testable
/// target. Issue #2 (domain + derivation) lands Culture/Event entities,
/// the deterministic status engine, and lineage DAG here. The GRDB store
/// is issue #3 and lives in the app target, not this package.
public enum RiseKit {
    /// Namespace marker for the domain layer.
    public static let domain = "RiseKit"

    /// Current build/CI milestone marker consumed by the app's debug surface.
    public static let milestone = "M0-skeleton"
}
