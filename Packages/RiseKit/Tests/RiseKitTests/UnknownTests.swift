import Foundation
import Testing

@testable import RiseKit

@Suite("Unknown-safe semantics")
struct UnknownTests {
    let cal = TestFixtures.utc
    let engine = StatusEngine(calendar: TestFixtures.utc)

    private func status(_ culture: Culture, _ ledger: EventLedger, now: Date) -> CultureStatus {
        engine.status(for: culture, ledger: ledger, now: now)
    }

    @Test("empty ledger derives unknown everywhere — never a fabricated value")
    func emptyLedgerAllUnknown() {
        let now = TestFixtures.date(cal, 2026, 4, 1, 12)
        let s = status(TestFixtures.culture(createdAt: now), EventLedger(), now: now)
        #expect(s.hoursSinceLastFeed == .unknown)
        #expect(s.risePhase == .unknown)
        // Ferment days are legitimately computable from createdAt alone.
        #expect(s.fermentDays == .known(0))
        #expect(s.dueWindow == .unknown)
    }

    @Test("no rise checks: rise phase is unknown, not 'flat' or any default")
    func noRiseChecks() {
        var ledger = EventLedger()
        #expect(throws: Never.self) {
            try ledger.append(TestFixtures.feed("f", at: TestFixtures.date(cal, 2026, 4, 1, 8)))
        }
        let s = status(TestFixtures.culture(createdAt: TestFixtures.date(cal, 2026, 1, 1)), ledger,
                       now: TestFixtures.date(cal, 2026, 4, 1, 12))
        #expect(s.risePhase == .unknown)
    }

    @Test("no cadence: due window unknown even with a recent feed")
    func noCadence() {
        var ledger = EventLedger()
        #expect(throws: Never.self) {
            try ledger.append(TestFixtures.feed("f", at: TestFixtures.date(cal, 2026, 4, 1, 8)))
        }
        let s = status(TestFixtures.culture(createdAt: TestFixtures.date(cal, 2026, 1, 1)), ledger,
                       now: TestFixtures.date(cal, 2026, 4, 1, 12))
        #expect(s.dueWindow == .unknown)
        #expect(s.hoursSinceLastFeed == .known(4.0))
    }

    @Test("no feeds: due window unknown even with a declared cadence")
    func noFeedWithCadence() {
        guard let cadence = FeedingCadence(everyHours: 12) else {
            Issue.record("cadence failed"); return
        }
        let s = status(TestFixtures.culture(cadence: cadence, createdAt: TestFixtures.date(cal, 2026, 1, 1)),
                       EventLedger(), now: TestFixtures.date(cal, 2026, 4, 1, 12))
        #expect(s.dueWindow == .unknown)
        #expect(s.hoursSinceLastFeed == .unknown)
    }

    @Test("future-dated feed yields unknown hours, never a negative value")
    func futureFeed() {
        var ledger = EventLedger()
        #expect(throws: Never.self) {
            try ledger.append(TestFixtures.feed("f", at: TestFixtures.date(cal, 2026, 4, 2, 8)))
        }
        let s = status(TestFixtures.culture(createdAt: TestFixtures.date(cal, 2026, 1, 1)), ledger,
                       now: TestFixtures.date(cal, 2026, 4, 1, 12))
        #expect(s.hoursSinceLastFeed == .unknown)
        #expect(s.dueWindow == .unknown)
    }

    @Test("future anchor yields unknown ferment days")
    func futureFermentAnchor() {
        var ledger = EventLedger()
        #expect(throws: Never.self) {
            try ledger.append(TestFixtures.event("b", kind: .bottle, at: TestFixtures.date(cal, 2026, 4, 5), payload: .bottle))
        }
        let s = status(TestFixtures.culture(createdAt: TestFixtures.date(cal, 2026, 1, 1)), ledger,
                       now: TestFixtures.date(cal, 2026, 4, 1))
        #expect(s.fermentDays == .unknown)
    }

    @Test("Derived never fabricates a value from unknown")
    func derivedAccessors() {
        let u: Derived<Double> = .unknown
        #expect(u.value == nil)
        #expect(!u.isKnown)
        let k: Derived<RiseStage> = .known(.rising)
        #expect(k.value == .rising)
        #expect(k.isKnown)
    }

    @Test("unknown in one field does not contaminate computable fields")
    func partialPropagation() {
        // Feed exists, rise check pending → hours known, phase unknown.
        var ledger = EventLedger()
        #expect(throws: Never.self) {
            try ledger.append(TestFixtures.feed("f", at: TestFixtures.date(cal, 2026, 4, 1, 8)))
        }
        let s = status(TestFixtures.culture(createdAt: TestFixtures.date(cal, 2026, 1, 1)), ledger,
                       now: TestFixtures.date(cal, 2026, 4, 1, 10))
        #expect(s.hoursSinceLastFeed == .known(2.0))
        #expect(s.risePhase == .unknown)
    }
}
