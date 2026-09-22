import Foundation

/// A derived quantity that may be legitimately absent.
///
/// `.unknown` is a first-class, renderable state — the engine NEVER coerces
/// missing data into a value (never invents "ready", "due", hours, etc.).
/// Wording here deliberately avoids any food-safety/safety vocabulary:
/// derived states describe time and user-logged observations only.
public enum Derived<Value: Hashable & Sendable>: Hashable, Sendable {
    case known(Value)
    case unknown

    public var isKnown: Bool {
        if case .known = self { true } else { false }
    }

    public var value: Value? {
        if case .known(let v) = self { v } else { nil }
    }
}

/// The due window implied by a culture's declared feeding cadence,
/// anchored at the last feed.
public struct DueWindow: Hashable, Sendable {
    /// Earliest the next feed is considered due (last feed + everyHours).
    public let opensAt: Date
    /// End of the grace period (opensAt + graceHours).
    public let closesAt: Date

    public init(opensAt: Date, closesAt: Date) {
        self.opensAt = opensAt
        self.closesAt = closesAt
    }

    /// Where `now` falls relative to the window.
    public enum Position: Hashable, Sendable {
        case beforeWindow
        case withinWindow
        case afterWindow
    }

    public func position(at now: Date) -> Position {
        if now < opensAt { .beforeWindow }
        else if now <= closesAt { .withinWindow }
        else { .afterWindow }
    }
}

/// Everything the app may render for one culture at one instant.
/// Every field is a pure function of (ledger, culture, calendar, `now`).
public struct CultureStatus: Hashable, Sendable {
    /// Elapsed hours since the most recent feed event (absolute elapsed
    /// time via `Calendar` hour components — DST-correct).
    public let hoursSinceLastFeed: Derived<Double>
    /// The user's most recent rise-check observation, unless a later
    /// feed/discard/bottle made it stale; `.unknown` when no valid check.
    public let risePhase: Derived<RiseStage>
    /// Whole calendar days in ferment (DST-safe, wall-clock day units):
    /// since the latest bottle event, or since the culture's start when
    /// it has never been bottled. `.unknown` when the anchor is in the
    /// future relative to `now`.
    public let fermentDays: Derived<Int>
    /// Due window from the user's declared cadence anchored at the last
    /// feed. `.unknown` when either is missing.
    public let dueWindow: Derived<DueWindow>

    public init(
        hoursSinceLastFeed: Derived<Double>,
        risePhase: Derived<RiseStage>,
        fermentDays: Derived<Int>,
        dueWindow: Derived<DueWindow>
    ) {
        self.hoursSinceLastFeed = hoursSinceLastFeed
        self.risePhase = risePhase
        self.fermentDays = fermentDays
        self.dueWindow = dueWindow
    }
}

/// Deterministic status engine.
///
/// The clock and calendar are always *supplied* — there is no `Date()`
/// read inside, so every derivation is reproducible in tests. Hour
/// arithmetic uses absolute elapsed time (`Calendar` `.hour` components);
/// day arithmetic uses wall-clock calendar days, both of which are
/// DST-safe by construction.
public struct StatusEngine: Sendable {
    public let calendar: Calendar

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    public func status(
        for culture: Culture,
        ledger: EventLedger,
        now: Date
    ) -> CultureStatus {
        let events = ledger.events(for: culture.id)

        let lastFeed = events.last { $0.kind == .feed }
        let hoursSinceFeed: Derived<Double>
        if let feed = lastFeed, feed.occurredAt <= now {
            let comps = calendar.dateComponents([.hour, .minute], from: feed.occurredAt, to: now)
            let hours = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60.0
            hoursSinceFeed = .known(hours)
        } else {
            // No feed yet, or the feed is dated in the future: unknown.
            hoursSinceFeed = .unknown
        }

        let risePhase = deriveRisePhase(events: events)

        let fermentDays = deriveFermentDays(culture: culture, events: events, now: now)

        let dueWindow: Derived<DueWindow>
        if let feed = lastFeed, feed.occurredAt <= now, let cadence = culture.cadence,
           let opensAt = calendar.date(byAdding: .hour, value: cadence.everyHours, to: feed.occurredAt),
           let closesAt = calendar.date(byAdding: .hour, value: cadence.graceHours, to: opensAt) {
            dueWindow = .known(DueWindow(opensAt: opensAt, closesAt: closesAt))
        } else {
            dueWindow = .unknown
        }

        return CultureStatus(
            hoursSinceLastFeed: hoursSinceFeed,
            risePhase: risePhase,
            fermentDays: fermentDays,
            dueWindow: dueWindow
        )
    }

    /// Rise phase = the stage of the latest rise check, invalidated to
    /// `.unknown` when a later feed/discard/bottle changed the jar's state
    /// (an observation from before that change says nothing about now).
    private func deriveRisePhase(events: [Event]) -> Derived<RiseStage> {
        var latestCheck: (date: Date, stage: RiseStage)?
        var invalidatingChange: Date?
        for event in events {
            switch event.kind {
            case .riseCheck:
                if case .riseCheck(let stage) = event.payload {
                    latestCheck = (event.occurredAt, stage)
                    invalidatingChange = nil
                }
            case .feed, .discard, .bottle:
                if let check = latestCheck, event.occurredAt > check.date {
                    invalidatingChange = event.occurredAt
                }
            default:
                break
            }
        }
        guard let check = latestCheck, invalidatingChange == nil else {
            return .unknown
        }
        return .known(check.stage)
    }

    /// Whole calendar days from the ferment anchor to `now`:
    /// latest bottle event, else the culture's start (split separation if
    /// present, else createdAt). Future anchors yield `.unknown` —
    /// never a negative or zeroed-out day count.
    private func deriveFermentDays(
        culture: Culture,
        events: [Event],
        now: Date
    ) -> Derived<Int> {
        let anchor: Date
        if let lastBottle = events.last(where: { $0.kind == .bottle }) {
            anchor = lastBottle.occurredAt
        } else {
            let separation = events.compactMap { event -> Date? in
                if case .split(_, let separatedAt) = event.payload { separatedAt } else { nil }
            }.max()
            anchor = max(separation ?? culture.createdAt, culture.createdAt)
        }
        guard anchor <= now else { return .unknown }
        let days = calendar.dateComponents([.day], from: anchor, to: now).day ?? 0
        return .known(max(0, days))
    }
}
