# Local feeding reminders — issue #7 evidence

## Behavior contract

- Reminders are off by default (`Culture.cadence == nil`).
- Each culture offers `Off`, `Every 12 hours`, `Every 24 hours`, and `Every 7 days`.
- Enabling a cadence asks for notification permission only when iOS reports `.notDetermined`.
- Disabling cancels that culture's pending requests without asking for permission.
- Every cadence change first cancels the culture's old requests, then schedules from its actual latest feed.
- Logging a feed repeats that replacement flow, using the new event's `occurredAt` as the anchor.
- Pending request identifiers are culture-scoped (`riselog.feed.<culture-id>.<index>`), so one culture cannot cancel another culture's reminders.
- Notification text is neutral: `Log a feed for <culture name>`.
- Scheduling uses `UNUserNotificationCenter` only. There is no push registration, server, account, or network dependency.

## Automated evidence

`ReminderPlanner` is pure RiseKit code. Linux `swift test` covers:

- default-off behavior;
- no guessed schedule without a feed anchor;
- 12-hour, 24-hour, and 7-day date math;
- roll-forward from the original feed anchor rather than from the current wall clock;
- re-anchoring after a newly logged feed;
- culture-scoped cancellation identifiers;
- exact neutral title/body wording.

The normal CI matrix also retains:

- the empty-allowlist zero-network gate;
- exact Xcode 26.0.1 / 17A400 / iOS SDK 26.0 selection;
- simulator app build and XCUITest journeys;
- source and built-product iPhone-only checks (`TARGETED_DEVICE_FAMILY = 1`, `UIDeviceFamily == [1]`);
- `com.infinityball.riselog` bundle-ID verification.

## Manual device evidence

**Status: pending.** This repository change was authored from a Linux executor with no attached iPhone. No hardware delivery result is claimed.

The issue remains incomplete until this checklist is executed on a physical iPhone and the observed result is recorded in the PR as **manual device evidence**:

1. Install the exact PR-head build on an iPhone.
2. Create or open a culture with a logged feed.
3. Confirm reminders initially show `Off` and no notification permission prompt appeared at launch or culture creation.
4. Select `Every 12 hours`; confirm the permission prompt appears only at this first enablement.
5. Allow notifications. Confirm the pending notification is local and reads `Log a feed for <culture name>`.
6. Log another feed and confirm the pending delivery date re-anchors to that feed time plus 12 hours.
7. Change to `Every 24 hours`; confirm the old pending requests are removed and replaced with the new cadence.
8. Select `Off`; confirm all pending requests for that culture are removed.
9. Repeat with a second culture and confirm changing one culture does not cancel the other's requests.

Record device model, iOS version, tested commit SHA, timestamps/expected fire dates, and pass/fail observations. Do not include notification content beyond the neutral culture name selected for testing.
