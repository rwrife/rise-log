import Foundation
import RiseKit
import UserNotifications

/// App-only adapter from RiseKit's pure `ReminderPlanner` to local iOS
/// notifications. No server, push token, or network dependency exists.
@MainActor
final class LocalReminderScheduler {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    /// Replaces pending reminders for one culture. Permission is requested
    /// only when enabling a cadence for the first time (`.notDetermined`).
    /// Turning reminders off always cancels locally without prompting.
    func reschedule(culture: Culture, lastFeedAt: Date?, now: Date = Date()) async {
        await cancel(cultureId: culture.id)
        guard culture.cadence != nil, lastFeedAt != nil else { return }

        let settings = await center.notificationSettings()
        let authorized: Bool
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            authorized = true
        case .notDetermined:
            authorized = (try? await center.requestAuthorization(options: [.alert, .sound])) == true
        case .denied:
            authorized = false
        @unknown default:
            authorized = false
        }
        guard authorized else { return }

        for request in ReminderPlanner.plan(for: culture, lastFeedAt: lastFeedAt, now: now) {
            let content = UNMutableNotificationContent()
            content.title = request.title
            content.body = request.body
            content.sound = .default
            content.userInfo = ["cultureId": culture.id.rawValue]

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: request.fireAt
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let notification = UNNotificationRequest(
                identifier: request.identifier,
                content: content,
                trigger: trigger
            )
            try? await center.add(notification)
        }
    }

    /// Cancels every pending occurrence for exactly one culture.
    func cancel(cultureId: CultureID) async {
        let prefix = ReminderPlanner.identifierPrefix(for: cultureId)
        let identifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
