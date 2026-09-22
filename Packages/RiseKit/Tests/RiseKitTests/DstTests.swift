import Foundation
import Testing

@testable import RiseKit

@Suite("DST-safe time derivation")
struct DstTests {
    let cal = TestFixtures.newYork

    /// 2026-03-08 is the US spring-forward day: 02:00 EST becomes 03:00 EDT.
    /// A feed at 22:00 on the night before must derive *absolute* elapsed
    /// hours, not naive wall-clock subtraction.
    @Test("elapsed hours across spring-forward are absolute, not wall-clock")
    func springForwardElapsed() {
        let feed = TestFixtures.date(cal, 2026, 3, 7, 22) // 22:00 EST (UTC-5)
        let now = TestFixtures.date(cal, 2026, 3, 8, 3)   // 03:00 EDT (UTC-4)

        // Wall-clock difference is 5 hours; absolute elapsed is 4 (one hour
        // was skipped). The engine must report the absolute value.
        var ledger = EventLedger()
        #expect(throws: Never.self) { try ledger.append(TestFixtures.feed("f", at: feed)) }
        let engine = StatusEngine(calendar: cal)
        let status = engine.status(for: TestFixtures.culture(createdAt: TestFixtures.date(cal, 2026, 1, 1, 9)),
                                   ledger: ledger, now: now)
        #expect(status.hoursSinceLastFeed == .known(4.0))
    }

    /// 2026-11-01 is the US fall-back day: 02:00 EDT becomes 01:00 EST.
    @Test("elapsed hours across fall-back include the repeated hour")
    func fallBackElapsed() {
        let feed = TestFixtures.date(cal, 2026, 10, 31, 22) // 22:00 EDT (UTC-4)
        let now = TestFixtures.date(cal, 2026, 11, 1, 2)    // 02:00 EST (UTC-5)

        // Wall-clock difference is 4 hours; absolute elapsed is 5.
        var ledger = EventLedger()
        #expect(throws: Never.self) { try ledger.append(TestFixtures.feed("f", at: feed)) }
        let engine = StatusEngine(calendar: cal)
        let status = engine.status(for: TestFixtures.culture(createdAt: TestFixtures.date(cal, 2026, 1, 1, 9)),
                                   ledger: ledger, now: now)
        #expect(status.hoursSinceLastFeed == .known(5.0))
    }

    @Test("ferment days across a DST change count calendar days")
    func fermentDaysAcrossDst() {
        // Bottle 2026-03-05 23:00 EST → now 2026-03-09 01:00 EDT = 3 calendar days.
        let bottle = TestFixtures.date(cal, 2026, 3, 5, 23)
        let now = TestFixtures.date(cal, 2026, 3, 9, 1)
        var ledger = EventLedger()
        #expect(throws: Never.self) {
            try ledger.append(TestFixtures.event("b", kind: .bottle, at: bottle, payload: .bottle))
        }
        let engine = StatusEngine(calendar: cal)
        let status = engine.status(for: TestFixtures.culture(createdAt: TestFixtures.date(cal, 2026, 1, 1, 9)),
                                   ledger: ledger, now: now)
        #expect(status.fermentDays == .known(3))
    }

    @Test("due window crossing spring-forward uses absolute hour addition")
    func dueWindowAcrossDst() {
        // Feed 2026-03-07 20:00 EST (01:00Z) with 8h cadence: window opens
        // 8 ABSOLUTE hours later = 09:00Z = 05:00 EDT — a naive wall-clock
        // "+8h" would wrongly say 04:00.
        let feed = TestFixtures.date(cal, 2026, 3, 7, 20)
        var ledger = EventLedger()
        #expect(throws: Never.self) { try ledger.append(TestFixtures.feed("f", at: feed)) }
        guard let cadence = FeedingCadence(everyHours: 8) else {
            Issue.record("cadence failed"); return
        }
        let engine = StatusEngine(calendar: cal)
        let status = engine.status(for: TestFixtures.culture(cadence: cadence, createdAt: TestFixtures.date(cal, 2026, 1, 1, 9)),
                                   ledger: ledger, now: TestFixtures.date(cal, 2026, 3, 8, 12))
        guard case .known(let window) = status.dueWindow else {
            Issue.record("expected known window"); return
        }
        #expect(window.opensAt == TestFixtures.date(cal, 2026, 3, 8, 5))
        // Absolute check: exactly 8 hours of real time between feed and open.
        #expect(window.opensAt.timeIntervalSince(feed) == 8 * 3600)
    }

    @Test("the same instant in two calendars derives the same elapsed hours")
    func calendarAgnosticElapsed() {
        let feed = TestFixtures.date(cal, 2026, 3, 7, 22)
        let now = TestFixtures.date(cal, 2026, 3, 8, 3)
        var ledger = EventLedger()
        #expect(throws: Never.self) { try ledger.append(TestFixtures.feed("f", at: feed)) }
        let culture = TestFixtures.culture(createdAt: TestFixtures.date(cal, 2026, 1, 1, 9))

        let inNY = StatusEngine(calendar: cal).status(for: culture, ledger: ledger, now: now)
        let inUtc = StatusEngine(calendar: TestFixtures.utc).status(for: culture, ledger: ledger, now: now)
        // Hour derivation is absolute elapsed time — timezone-independent.
        #expect(inNY.hoursSinceLastFeed == inUtc.hoursSinceLastFeed)
        #expect(inNY.hoursSinceLastFeed == .known(4.0))
    }
}
