import Foundation

/// The sample culture offered by first-run onboarding (issue #4).
///
/// Lives in RiseKit so the seeded event set is deterministic and
/// unit-testable on Linux: feeding it to `StatusEngine` must always
/// produce a *known* badge ("Fed 12h · peaked"), proving the empty-state
/// → sample → badge loop end to end without a simulator.
public enum SampleData {
    public static let cultureID = CultureID(rawValue: "sample-starter")
    public static let cultureName = "Sample starter"

    /// The sample culture, `createdAt` = `anchor - 5 days`.
    public static func culture(anchor: Date, calendar: Calendar) -> Culture {
        Culture(
            id: cultureID,
            name: cultureName,
            type: .starter,
            createdAt: calendar.date(byAdding: .day, value: -5, to: anchor) ?? anchor
        )
    }

    /// The sample ledger: a feed 2 days ago, a discard 26h ago, a feed
    /// 14h ago, and a rise check (peaked) 12h ago — the check is the
    /// latest event so it stays valid, and at the anchor instant the
    /// badge renders exactly `Fed 14h · peaked`. Whole-hour offsets keep
    /// the text deterministic.
    public static func events(anchor: Date, calendar: Calendar) -> [Event] {
        func shifted(_ hours: Int) -> Date {
            calendar.date(byAdding: .hour, value: -hours, to: anchor) ?? anchor
        }
        return [
            Event(id: EventID(rawValue: "sample-e1"), cultureId: cultureID,
                  kind: .feed, occurredAt: shifted(48),
                  payload: .feed(FeedAmount(flourGrams: 50, waterGrams: 50))),
            Event(id: EventID(rawValue: "sample-e2"), cultureId: cultureID,
                  kind: .discard, occurredAt: shifted(26),
                  payload: .discard(removedGrams: 40)),
            Event(id: EventID(rawValue: "sample-e3"), cultureId: cultureID,
                  kind: .feed, occurredAt: shifted(14),
                  payload: .feed(FeedAmount(flourGrams: 50, waterGrams: 50))),
            Event(id: EventID(rawValue: "sample-e4"), cultureId: cultureID,
                  kind: .riseCheck, occurredAt: shifted(12),
                  payload: .riseCheck(.peaked)),
        ]
    }

    /// Inserts the sample culture + ledger into the store. Idempotent by
    /// design: duplicate event ids / existing culture surface as errors
    /// from the store, so callers seed exactly once from onboarding.
    public static func seed(into store: RiseLogStore, anchor: Date, calendar: Calendar) throws {
        try store.saveCulture(culture(anchor: anchor, calendar: calendar))
        for event in events(anchor: anchor, calendar: calendar) {
            try store.insertEvent(event, loggedAt: anchor)
        }
    }
}
