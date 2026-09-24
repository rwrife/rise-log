import Foundation
import Testing

@testable import RiseKit

/// Wording + badge rules for issue #4 acceptance:
/// "Fed 8h · rising" style badges, no safety/edibility language,
/// unknown states rendered explicitly. These strings ARE the UI copy —
/// pinning them here is what lets the journey tests treat them as
/// stable identifiers of truth.
@Suite("Derived status: badge wording")
struct DerivedStatusTextTests {
    let utc = TestFixtures.utc
    let engine = StatusEngine(calendar: TestFixtures.utc)

    private func status(_ events: [Event], culture: Culture, at now: Date) -> CultureStatus {
        var ledger = EventLedger()
        for e in events { try? ledger.append(e) }
        return engine.status(for: culture, ledger: ledger, now: now)
    }

    @Test("fresh culture with no events renders the explicit unknown badge")
    func unknownBadge() {
        let created = TestFixtures.date(utc, 2026, 3, 1)
        let now = TestFixtures.date(utc, 2026, 3, 5)
        let s = status([], culture: TestFixtures.culture(createdAt: created), at: now)
        // createdAt anchor makes fermentDays known -> Day line, not unknown.
        #expect(s.badgeText == "Day 4")
        // With no anchor at all (created in the future) it must be the
        // literal unknown badge.
        let future = TestFixtures.culture(createdAt: TestFixtures.date(utc, 2026, 4, 1))
        let s2 = status([], culture: future, at: now)
        #expect(s2.badgeText == "Unknown — no checks logged")
    }

    @Test("feed badge: hours floor + still-valid rise check suffix")
    func feedBadge() {
        let created = TestFixtures.date(utc, 2026, 3, 1)
        let feed = TestFixtures.feed("e1", at: TestFixtures.date(utc, 2026, 3, 9, 8))
        let now = TestFixtures.date(utc, 2026, 3, 9, 16, 30)
        let culture = TestFixtures.culture(createdAt: created)
        #expect(status([feed], culture: culture, at: now).badgeText == "Fed 8h")

        let check = TestFixtures.event("e2", kind: .riseCheck,
            at: TestFixtures.date(utc, 2026, 3, 9, 15),
            payload: .riseCheck(.rising))
        #expect(status([feed, check], culture: culture, at: now).badgeText == "Fed 8h · rising")

        // A later feed invalidates the check: suffix drops, never guesses.
        let feed2 = TestFixtures.feed("e3", at: TestFixtures.date(utc, 2026, 3, 9, 16))
        #expect(status([feed, check, feed2], culture: culture, at: now).badgeText == "Fed 0h")
    }

    @Test("accessibility label spells units out")
    func accessibilityLabels() {
        let created = TestFixtures.date(utc, 2026, 3, 1)
        let feed = TestFixtures.feed("e1", at: TestFixtures.date(utc, 2026, 3, 9, 8))
        let now = TestFixtures.date(utc, 2026, 3, 9, 16)
        let culture = TestFixtures.culture(createdAt: created)
        let s = status([feed], culture: culture, at: now)
        #expect(s.badgeAccessibilityLabel == "Fed 8 hours ago")

        let check = TestFixtures.event("e2", kind: .riseCheck,
            at: TestFixtures.date(utc, 2026, 3, 9, 15),
            payload: .riseCheck(.peaked))
        let s2 = status([feed, check], culture: culture, at: now)
        #expect(s2.badgeAccessibilityLabel == "Fed 8 hours ago, observed peaked")

        let future = TestFixtures.culture(createdAt: TestFixtures.date(utc, 2026, 4, 1))
        #expect(status([], culture: future, at: now).badgeAccessibilityLabel
                == "Unknown, no checks logged")
    }

    @Test("detail lines: unknown states are explicit, never blank")
    func detailLines() {
        let future = TestFixtures.culture(createdAt: TestFixtures.date(utc, 2026, 4, 1))
        let now = TestFixtures.date(utc, 2026, 3, 5)
        let s = status([], culture: future, at: now)
        #expect(s.lastFeedLineText == "Last feed: Unknown — no feeds logged")
        #expect(s.risePhaseLineText == "Rise phase: Unknown — no checks logged")
        #expect(s.fermentDaysLineText == "In ferment: Unknown")
        #expect(DueWindow.cadenceLine(due: s.dueWindow, now: now)
                == "Due: Unknown — no cadence set")
    }

    @Test("cadence line reflects window position")
    func cadencePositions() {
        let created = TestFixtures.date(utc, 2026, 3, 1)
        guard let cadence = FeedingCadence(everyHours: 12, graceHours: 2) else {
            Issue.record("cadence fixture rejected"); return
        }
        let culture = TestFixtures.culture(cadence: cadence, createdAt: created)
        let feed = TestFixtures.feed("e1", at: TestFixtures.date(utc, 2026, 3, 9, 8))
        let before = TestFixtures.date(utc, 2026, 3, 9, 12)   // 4h after feed
        let within = TestFixtures.date(utc, 2026, 3, 9, 21)   // 13h after
        let after = TestFixtures.date(utc, 2026, 3, 9, 23)    // 15h after
        #expect(DueWindow.cadenceLine(
            due: status([feed], culture: culture, at: before).dueWindow, now: before)
            == "Due: not yet")
        #expect(DueWindow.cadenceLine(
            due: status([feed], culture: culture, at: within).dueWindow, now: within)
            == "Due: within window")
        #expect(DueWindow.cadenceLine(
            due: status([feed], culture: culture, at: after).dueWindow, now: after)
            == "Due: past window")
    }

    /// Acceptance: badge text contains no safety/edibility language.
    /// Scan EVERY user-facing string builder against a forbidden-vocabulary
    /// list, across a broad matrix of ledger shapes.
    @Test("no safety/edibility vocabulary anywhere in derived wording")
    func noSafetyLanguage() {
        let forbidden = [
            "safe", "unsafe", "ready", "spoil", "bad", "rot", "mold",
            "danger", "health", "toxic", "smell", "taste", "eat",
            "discard it", "feed it now", "smells",
        ]
        var corpus: [String] = []
        for daysOld in [0, 1, 6, 60] {
            let created = TestFixtures.date(utc, 2026, 1, 1)
            let now = TestFixtures.date(utc, 2026, 1, 1 + daysOld)
            let ledgerEvents: [[Event]] = [
                [],
                [TestFixtures.feed("f1", at: TestFixtures.date(utc, 2026, 1, 1))],
                [TestFixtures.feed("f1", at: TestFixtures.date(utc, 2026, 1, 1)),
                 TestFixtures.event("c1", kind: .riseCheck,
                                    at: TestFixtures.date(utc, 2026, 1, 1),
                                    payload: .riseCheck(.flat))],
                [TestFixtures.event("b1", kind: .bottle,
                                    at: TestFixtures.date(utc, 2026, 1, 1),
                                    payload: .bottle)],
            ]
            for events in ledgerEvents {
                let culture = TestFixtures.culture(createdAt: created)
                let s = status(events, culture: culture, at: now)
                corpus += [
                    s.badgeText, s.badgeAccessibilityLabel, s.lastFeedLineText,
                    s.risePhaseLineText, s.fermentDaysLineText,
                    DueWindow.cadenceLine(due: s.dueWindow, now: now),
                ]
            }
        }
        for stage in RiseStage.allCases {
            corpus += ["Rise check — \(stage.displayName)"]
        }
        #expect(corpus.count >= 20)
        for line in corpus {
            let lower = line.lowercased()
            for word in forbidden {
                #expect(!lower.contains(word),
                        "forbidden vocabulary \(word) in: \(line)")
            }
        }
    }
}
