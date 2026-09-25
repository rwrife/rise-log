import Foundation

// Badge/status wording for derived culture state (issue #4).
//
// Lives in the pure package — NOT in the app — for two reasons:
// 1. The wording rules are acceptance criteria ("no safety/edibility
//    language", "unknown states render explicitly") and are unit-testable
//    on Linux CI.
// 2. The app target carries NO RiseKit test host, so any wording that
//    must be test-verified belongs here.
//
// Vocabulary rules (PLAN.md risk table — badges must never read as
// food-safety advice):
// - Words like "safe", "ready", "spoiled", "bad", "smell", "look"
//   NEVER appear in any output; the wording test scans for them.
// - Absent data renders as the explicit literal "Unknown — no checks
//   logged" (or the per-field Unknown forms), never a guessed value.

extension CultureStatus {
    /// The jar-wall badge line: `Fed 8h · rising`, `Fed 0h`, `Day 6`,
    /// or `Unknown — no checks logged`.
    ///
    /// Precedence (most recent known fact wins):
    /// - last feed known → `"Fed {h}h"` (floor); a still-valid rise-check
    ///   appends `· {stage}` — an unobserved jar is silent, not guessed,
    /// - else ferment-days known → `"Day {n}"` (age since bottle/start),
    /// - else → the explicit unknown line.
    public var badgeText: String {
        if case .known(let hours) = hoursSinceLastFeed {
            let feed = "Fed \(Int(floor(hours)))h"
            if case .known(let stage) = risePhase {
                return "\(feed) · \(stage.displayName)"
            }
            return feed
        }
        if case .known(let days) = fermentDays {
            return "Day \(days)"
        }
        return Self.unknownBadgeText
    }

    /// The explicit unknown badge. A brand-new jar with no events and no
    /// checks must still tell the truth about what it knows.
    public static let unknownBadgeText = "Unknown — no checks logged"

    /// VoiceOver line for the badge: spells out "hours"/"days" so the
    /// abbreviated visible text never reads as "F e d 8 h".
    public var badgeAccessibilityLabel: String {
        switch (hoursSinceLastFeed, risePhase, fermentDays) {
        case (.known(let hours), let phase, _):
            let h = Int(floor(hours))
            let feed = "Fed \(h) hour\(h == 1 ? "" : "s") ago"
            if case .known(let stage) = phase {
                return "\(feed), observed \(stage.displayName)"
            }
            return feed
        case (.unknown, _, .known(let days)):
            return "Day \(days) in ferment"
        default:
            return "Unknown, no checks logged"
        }
    }

    /// The detail-screen "Last feed" row value.
    public var lastFeedLineText: String {
        if case .known(let hours) = hoursSinceLastFeed {
            return "Last feed: \(Int(floor(hours)))h ago"
        }
        return "Last feed: Unknown — no feeds logged"
    }

    /// The detail-screen "Rise phase" row value.
    public var risePhaseLineText: String {
        if case .known(let stage) = risePhase {
            return "Rise phase: \(stage.displayName)"
        }
        return "Rise phase: Unknown — no checks logged"
    }

    /// The detail-screen "In ferment" row value.
    public var fermentDaysLineText: String {
        if case .known(let days) = fermentDays {
            return "In ferment: day \(days)"
        }
        return "In ferment: Unknown"
    }
}

extension DueWindow {
    /// Cadence line for the detail screen, given `now`. `.unknown` when
    /// the engine has no due window — never a fabricated schedule.
    public static func cadenceLine(due: Derived<DueWindow>, now: Date) -> String {
        guard let window = due.value else {
            return "Due: Unknown — no cadence set"
        }
        switch window.position(at: now) {
        case .beforeWindow:
            return "Due: not yet"
        case .withinWindow:
            return "Due: within window"
        case .afterWindow:
            return "Due: past window"
        }
    }
}

extension RiseStage {
    /// User-facing label for the user's own observation. Plain stage
    /// names only — no interpretation appended.
    public var displayName: String {
        switch self {
        case .flat: return "flat"
        case .rising: return "rising"
        case .peaked: return "peaked"
        case .falling: return "falling"
        }
    }
}
