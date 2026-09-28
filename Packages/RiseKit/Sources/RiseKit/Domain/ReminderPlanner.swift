import Foundation

/// Pure deterministic planner for local feeding reminders (issue #7).
///
/// Acceptance rules:
/// - Reminders are per-culture and opt-in (off when cadence is nil).
/// - Schedules re-anchor from the actual last feed event, not from wall-clock drift.
/// - Neutral wording without food-safety or edibility judgment: "Log a feed for <Name>".
/// - Date math is fully extracted here so Linux CI exercises the recurrence/anchor rules.
public struct ReminderNotificationRequest: Hashable, Sendable {
    public let identifier: String
    public let cultureId: CultureID
    public let title: String
    public let body: String
    public let fireAt: Date

    public init(
        identifier: String,
        cultureId: CultureID,
        title: String,
        body: String,
        fireAt: Date
    ) {
        self.identifier = identifier
        self.cultureId = cultureId
        self.title = title
        self.body = body
        self.fireAt = fireAt
    }
}

public enum ReminderPlanner {
    public static let defaultOccurrenceCount = 3

    public static func identifierPrefix(for cultureId: CultureID) -> String {
        "riselog.feed.\(cultureId.rawValue)."
    }

    public static func reminderBody(for cultureName: String) -> String {
        "Log a feed for \(cultureName)"
    }

    public static func reminderTitle() -> String {
        "Feeding reminder"
    }

    /// Plans local reminder requests for one culture.
    ///
    /// Returns an empty list when:
    /// - `culture.cadence` is nil (reminders are off by default)
    /// - `lastFeedAt` is nil (no feed has occurred yet, so there is no anchor to pace from)
    /// - `occurrenceCount` <= 0
    public static func plan(
        for culture: Culture,
        lastFeedAt: Date?,
        now: Date,
        occurrenceCount: Int = defaultOccurrenceCount
    ) -> [ReminderNotificationRequest] {
        guard let cadence = culture.cadence,
              let anchor = lastFeedAt,
              occurrenceCount > 0 else {
            return []
        }

        let stepSeconds = Double(cadence.everyHours) * 3_600.0
        guard stepSeconds > 0 else { return [] }

        var nextFireAt: Date
        if anchor > now {
            nextFireAt = anchor.addingTimeInterval(stepSeconds)
        } else {
            let elapsed = now.timeIntervalSince(anchor)
            let stepsElapsed = floor(elapsed / stepSeconds)
            nextFireAt = anchor.addingTimeInterval((stepsElapsed + 1.0) * stepSeconds)
            if nextFireAt <= now {
                nextFireAt = nextFireAt.addingTimeInterval(stepSeconds)
            }
        }

        let prefix = identifierPrefix(for: culture.id)
        let title = reminderTitle()
        let body = reminderBody(for: culture.name)

        var requests: [ReminderNotificationRequest] = []
        for index in 0..<occurrenceCount {
            let fireAt = nextFireAt.addingTimeInterval(Double(index) * stepSeconds)
            requests.append(
                ReminderNotificationRequest(
                    identifier: "\(prefix)\(index)",
                    cultureId: culture.id,
                    title: title,
                    body: body,
                    fireAt: fireAt
                )
            )
        }
        return requests
    }
}
