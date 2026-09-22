import Foundation
import Testing

@testable import RiseKit

/// Shared helpers for the RiseKit test suite.
enum TestFixtures {
    /// New York — observes US DST (spring-forward + fall-back).
    static let newYork: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal
    }()

    /// UTC — no DST, for baseline math.
    static let utc: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    /// Builds a date in the given calendar's timezone. All test wall-clock
    /// times avoid the ambiguous DST fold (use :00–:59 outside 01:00–02:00
    /// on change days) so construction is unambiguous.
    static func date(_ cal: Calendar, _ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = y
        comps.month = mo
        comps.day = d
        comps.hour = h
        comps.minute = mi
        guard let date = cal.date(from: comps) else {
            Issue.record("fixture date construction failed")
            return Date(timeIntervalSince1970: 0)
        }
        return date
    }

    static func culture(
        id: String = "c1",
        cadence: FeedingCadence? = nil,
        createdAt: Date
    ) -> Culture {
        Culture(id: CultureID(rawValue: id), name: "Test jar", type: .starter, cadence: cadence, createdAt: createdAt)
    }

    static func event(
        _ id: String,
        culture: String = "c1",
        kind: Event.Kind,
        at date: Date,
        payload: EventPayload
    ) -> Event {
        Event(id: EventID(rawValue: id), cultureId: CultureID(rawValue: culture), kind: kind, occurredAt: date, payload: payload)
    }

    static func feed(_ id: String, at date: Date, culture: String = "c1", amounts: FeedAmount = .unspecified) -> Event {
        event(id, culture: culture, kind: .feed, at: date, payload: .feed(amounts))
    }
}
