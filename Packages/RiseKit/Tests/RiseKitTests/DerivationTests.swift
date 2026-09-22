import Foundation
import Testing

@testable import RiseKit

@Suite("StatusEngine derivation math")
struct DerivationTests {
    let cal = TestFixtures.utc

    @Test("hours since last feed is elapsed time from the most recent feed")
    func hoursSinceFeed() {
        let created = TestFixtures.date(cal, 2026, 1, 1, 9)
        let feed1 = TestFixtures.date(cal, 2026, 3, 1, 6)
        let feed2 = TestFixtures.date(cal, 2026, 3, 2, 21, 30)
        let now = TestFixtures.date(cal, 2026, 3, 3, 6)

        var ledger = EventLedger()
        #expect(throws: Never.self) { try ledger.append(TestFixtures.feed("e1", at: feed1)) }
        #expect(throws: Never.self) { try ledger.append(TestFixtures.feed("e2", at: feed2)) }
        // An unrelated note must not affect the feed calculation.
        #expect(throws: Never.self) {
            try ledger.append(TestFixtures.event("e3", kind: .note, at: now, payload: .note("smells good")))
        }

        let engine = StatusEngine(calendar: cal)
        let status = engine.status(for: TestFixtures.culture(createdAt: created), ledger: ledger, now: now)

        // 21:30 → next-day 06:00 = 8h30m.
        #expect(status.hoursSinceLastFeed == .known(8.5))
    }

    @Test("rise phase reflects the latest rise check")
    func risePhaseLatestCheck() {
        let created = TestFixtures.date(cal, 2026, 1, 1, 9)
        let check1 = TestFixtures.date(cal, 2026, 5, 1, 8)
        let check2 = TestFixtures.date(cal, 2026, 5, 1, 14)
        let now = TestFixtures.date(cal, 2026, 5, 1, 15)

        var ledger = EventLedger()
        #expect(throws: Never.self) {
            try ledger.append(TestFixtures.event("e1", kind: .riseCheck, at: check1, payload: .riseCheck(.flat)))
        }
        #expect(throws: Never.self) {
            try ledger.append(TestFixtures.event("e2", kind: .riseCheck, at: check2, payload: .riseCheck(.peaked)))
        }

        let engine = StatusEngine(calendar: cal)
        let status = engine.status(for: TestFixtures.culture(createdAt: created), ledger: ledger, now: now)
        #expect(status.risePhase == .known(.peaked))
    }

    @Test("a later feed/discard/bottle invalidates an earlier rise check")
    func riseCheckInvalidation() {
        let created = TestFixtures.date(cal, 2026, 1, 1, 9)
        let check = TestFixtures.date(cal, 2026, 5, 1, 8)
        let now = TestFixtures.date(cal, 2026, 5, 1, 12)

        for kind in [Event.Kind.feed, .discard, .bottle] {
            var ledger = EventLedger()
            #expect(throws: Never.self) {
                try ledger.append(TestFixtures.event("c", kind: .riseCheck, at: check, payload: .riseCheck(.rising)))
            }
            let payload: EventPayload = switch kind {
            case .feed: .feed(.unspecified)
            case .discard: .discard(removedGrams: 50)
            default: .bottle
            }
            #expect(throws: Never.self) {
                try ledger.append(TestFixtures.event("x", kind: kind, at: TestFixtures.date(cal, 2026, 5, 1, 10), payload: payload))
            }
            let engine = StatusEngine(calendar: cal)
            let status = engine.status(for: TestFixtures.culture(createdAt: created), ledger: ledger, now: now)
            #expect(status.risePhase == .unknown, "\(kind) after the check must void it")
        }
    }

    @Test("bake and note events do not invalidate a rise check")
    func benignEventsKeepRisePhase() {
        let created = TestFixtures.date(cal, 2026, 1, 1, 9)
        let check = TestFixtures.date(cal, 2026, 5, 1, 8)
        let now = TestFixtures.date(cal, 2026, 5, 1, 18)

        var ledger = EventLedger()
        #expect(throws: Never.self) {
            try ledger.append(TestFixtures.event("c", kind: .riseCheck, at: check, payload: .riseCheck(.rising)))
            try ledger.append(TestFixtures.event("b", kind: .bake, at: TestFixtures.date(cal, 2026, 5, 1, 9), payload: .bake(flourUsedGrams: 200)))
            try ledger.append(TestFixtures.event("n", kind: .note, at: TestFixtures.date(cal, 2026, 5, 1, 10), payload: .note("bubbly")))
        }
        let engine = StatusEngine(calendar: cal)
        let status = engine.status(for: TestFixtures.culture(createdAt: created), ledger: ledger, now: now)
        #expect(status.risePhase == .known(.rising))
    }

    @Test("a rise check after an invalidating event is valid again")
    func checkAfterChangeIsFresh() {
        let created = TestFixtures.date(cal, 2026, 1, 1, 9)
        var ledger = EventLedger()
        #expect(throws: Never.self) {
            try ledger.append(TestFixtures.feed("f", at: TestFixtures.date(cal, 2026, 5, 1, 6)))
            try ledger.append(TestFixtures.event("c", kind: .riseCheck, at: TestFixtures.date(cal, 2026, 5, 1, 12), payload: .riseCheck(.peaked)))
        }
        let engine = StatusEngine(calendar: cal)
        let status = engine.status(for: TestFixtures.culture(createdAt: created), ledger: ledger,
                                   now: TestFixtures.date(cal, 2026, 5, 1, 13))
        #expect(status.risePhase == .known(.peaked))
    }

    @Test("ferment days count from the latest bottle event")
    func fermentDaysFromBottle() {
        let start = TestFixtures.date(cal, 2026, 1, 1, 9)
        let bottle1 = TestFixtures.date(cal, 2026, 6, 1, 10)
        let bottle2 = TestFixtures.date(cal, 2026, 6, 5, 10)
        let now = TestFixtures.date(cal, 2026, 6, 8, 9) // 2d23h after bottle2

        var ledger = EventLedger()
        #expect(throws: Never.self) {
            try ledger.append(TestFixtures.event("b1", kind: .bottle, at: bottle1, payload: .bottle))
            try ledger.append(TestFixtures.event("b2", kind: .bottle, at: bottle2, payload: .bottle))
        }
        let engine = StatusEngine(calendar: cal)
        let status = engine.status(for: TestFixtures.culture(createdAt: start), ledger: ledger, now: now)
        #expect(status.fermentDays == .known(2))
    }

    @Test("ferment days fall back to culture start, or split separation when later")
    func fermentDaysFromStartOrSeparation() {
        let engine = StatusEngine(calendar: cal)
        let created = TestFixtures.date(cal, 2026, 1, 1, 9)
        let now = TestFixtures.date(cal, 2026, 1, 6, 9)

        // Never bottled: anchored at createdAt → 5 days.
        let plain = engine.status(for: TestFixtures.culture(createdAt: created), ledger: EventLedger(), now: now)
        #expect(plain.fermentDays == .known(5))

        // Split child separated 2 days after record creation: anchored at separation.
        let separatedAt = TestFixtures.date(cal, 2026, 1, 3, 9)
        var ledger = EventLedger()
        #expect(throws: Never.self) {
            try ledger.append(TestFixtures.event(
                "s", culture: "child", kind: .split, at: separatedAt,
                payload: .split(parent: CultureID(rawValue: "c1"), separatedAt: separatedAt)))
        }
        let child = Culture(id: CultureID(rawValue: "child"), name: "gift jar", type: .starter,
                            createdAt: created)
        let childStatus = engine.status(for: child, ledger: ledger, now: now)
        #expect(childStatus.fermentDays == .known(3))
    }

    @Test("due window anchors at last feed with declared cadence")
    func dueWindowMath() {
        let created = TestFixtures.date(cal, 2026, 1, 1, 9)
        let feedTime = TestFixtures.date(cal, 2026, 7, 1, 8)
        var ledger = EventLedger()
        #expect(throws: Never.self) { try ledger.append(TestFixtures.feed("f", at: feedTime)) }

        guard let cadence = FeedingCadence(everyHours: 12, graceHours: 3) else {
            Issue.record("cadence construction failed"); return
        }
        let engine = StatusEngine(calendar: cal)
        let culture = TestFixtures.culture(cadence: cadence, createdAt: created)

        let status = engine.status(for: culture, ledger: ledger,
                                   now: TestFixtures.date(cal, 2026, 7, 1, 14))
        guard case .known(let window) = status.dueWindow else {
            Issue.record("expected known window"); return
        }
        #expect(window.opensAt == TestFixtures.date(cal, 2026, 7, 1, 20))
        #expect(window.closesAt == TestFixtures.date(cal, 2026, 7, 1, 23))
        #expect(window.position(at: TestFixtures.date(cal, 2026, 7, 1, 14)) == .beforeWindow)
        #expect(window.position(at: TestFixtures.date(cal, 2026, 7, 1, 21)) == .withinWindow)
        #expect(window.position(at: TestFixtures.date(cal, 2026, 7, 2, 1)) == .afterWindow)
    }

    @Test("engine exposes no hidden clock: identical inputs give identical output")
    func deterministic() {
        let created = TestFixtures.date(cal, 2026, 1, 1, 9)
        let feedTime = TestFixtures.date(cal, 2026, 3, 1, 6)
        var ledger = EventLedger()
        #expect(throws: Never.self) { try ledger.append(TestFixtures.feed("f", at: feedTime)) }
        let engine = StatusEngine(calendar: cal)
        let culture = TestFixtures.culture(createdAt: created)
        let now = TestFixtures.date(cal, 2026, 3, 1, 18)
        let a = engine.status(for: culture, ledger: ledger, now: now)
        let b = engine.status(for: culture, ledger: ledger, now: now)
        #expect(a == b)
    }
}
