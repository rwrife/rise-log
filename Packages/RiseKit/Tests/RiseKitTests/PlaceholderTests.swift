import Testing
@testable import RiseKit

@Suite("Namespace markers")
struct PlaceholderTests {
    @Test("domain namespace is reachable")
    func domainNamespace() {
        #expect(RiseKit.domain == "RiseKit")
    }

    @Test("milestone marker is set for M1")
    func milestoneMarker() {
        #expect(RiseKit.milestone == "M1-domain")
    }

    @Test("markers are pure constants")
    func constantsAreStable() {
        let first = (RiseKit.domain, RiseKit.milestone)
        let second = (RiseKit.domain, RiseKit.milestone)
        #expect(first == second)
    }
}
