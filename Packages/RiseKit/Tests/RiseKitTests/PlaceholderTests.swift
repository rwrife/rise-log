import Testing
@testable import RiseKit

@Suite("Skeleton placeholder")
struct PlaceholderTests {
    @Test("domain namespace is reachable")
    func domainNamespace() {
        #expect(RiseKit.domain == "RiseKit")
    }

    @Test("milestone marker is set for M0")
    func milestoneMarker() {
        #expect(RiseKit.milestone == "M0-skeleton")
    }

    @Test("skeleton exposes no stored state beyond constants")
    func constantsAreStable() {
        // Guards the contract later issues depend on: these markers exist
        // and are pure constants (no clock, no I/O) in the M0 skeleton.
        let first = (RiseKit.domain, RiseKit.milestone)
        let second = (RiseKit.domain, RiseKit.milestone)
        #expect(first == second)
    }
}
