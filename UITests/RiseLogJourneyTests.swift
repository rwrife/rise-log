import Foundation
import XCTest

/// Issue #4 acceptance journey (XCUITest, pinned simulator CI):
/// create culture → log feed → badge updates on the wall.
/// Plus the empty-state/sample loop, append-only undo + correct
/// affordances, and the same core loop at AX5 Dynamic Type with the
/// VoiceOver label assertion.
///
/// Every launch resets the on-disk store via `-uitest-reset-store` so
/// journeys start from the true empty state. Identifiers match the app
/// sources; List rows are revealed via direction-alternating scrolling
/// (large-type blind zone is fleet-known).
///
/// This is SIMULATOR evidence only — launch + interaction results here
/// are never device results.
@MainActor
final class RiseLogJourneyTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest-reset-store"]
    }

    // MARK: - Helpers

    /// Container identifiers can surface as any element type depending on
    /// the SwiftUI backing view; query loosely to stay deterministic.
    private func expect(_ identifier: String, timeout: TimeInterval = 15, _ message: String? = nil) {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      message ?? "element \(identifier) missing")
    }

    /// Fleet-known trap at large text sizes: found != hittable (lazy List
    /// rows below the AX5 viewport exist but never get tapped), and a tap
    /// on an unhittable element silently does nothing. Scroll (alternating
    /// direction — rows can be pushed ABOVE the viewport by the keyboard)
    /// until hittable, and fail loudly with provenance otherwise.
    private func tap(_ identifier: String, timeout: TimeInterval = 15) {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "tap target \(identifier) missing")
        if element.isHittable { element.tap(); return }
        let deadline = Date().addingTimeInterval(timeout)
        var scrollUpFirst = true // reveal content below first
        while Date() < deadline {
            if scrollUpFirst { app.swipeUp() } else { app.swipeDown() }
            scrollUpFirst.toggle()
            if element.waitForHittable(timeout: 2) { element.tap(); return }
        }
        XCTAssertTrue(element.isHittable,
                      "tap target \(identifier) exists but never became hittable")
        element.tap()
    }

    /// Alternating bounded scroll until a substring-bearing text exists.
    private func revealText(_ substring: String, timeout: TimeInterval = 15) -> XCUIElement {
        let element = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", substring)
        ).firstMatch
        if element.waitForExistence(timeout: 2) { return element }
        let deadline = Date().addingTimeInterval(timeout)
        var scrollDownFirst = true
        while Date() < deadline {
            if scrollDownFirst { app.swipeDown() } else { app.swipeUp() }
            scrollDownFirst.toggle()
            if element.waitForExistence(timeout: 1) { return element }
        }
        return element
    }

    @discardableResult
    private func expectText(_ substring: String, timeout: TimeInterval = 15) -> Bool {
        revealText(substring, timeout: timeout).exists
    }

    private func createCultureNamed(_ name: String) {
        tap("wall.add-culture")
        let field = app.textFields["create.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(name)
        tap("create.save")
    }

    /// Open a wall row. NavigationLink cells surface as BUTTONS whose label
    /// contains the culture name (tapping the staticText inside a cell does
    /// not fire the link — fleet-proven trap).
    private func openRow(named name: String) {
        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", name)
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "wall row for \(name) missing")
        row.tap()
    }

    /// Wall badge assertion. SwiftUI may merge a NavigationLink's label
    /// into ONE accessibility element (row button label contains the badge)
    /// or keep child staticTexts visible (fleet evidence varies per layout).
    /// Poll BOTH shapes; assert against the VoiceOver label form (a custom
    /// accessibilityLabel replaces the visible text in the AX tree).
    private func expectWallBadge(name: String, badgeLabel fragment: String,
                                 timeout: TimeInterval = 15) -> Bool {
        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", name, fragment)
        ).firstMatch
        let text = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", fragment)
        ).firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        var scrollDownFirst = true
        while Date() < deadline {
            if row.exists || text.exists { return true }
            if scrollDownFirst { app.swipeDown() } else { app.swipeUp() }
            scrollDownFirst.toggle()
        }
        return row.exists || text.exists
    }

    // MARK: - Journeys

    /// THE acceptance journey: create culture → log feed → badge updates
    /// on the wall. Feed is 2 taps (open sheet, Log Feed).
    func testCreateThenFeedBadgeUpdatesOnWall() throws {
        app.launch()

        // Empty state proves the onboarding surface exists.
        expect("wall.empty")

        createCultureNamed("Journey jar")

        // New jar: explicit unknown badge (no feed/checks yet), asserted on
        // the wall row (see expectWallBadge for why both AX shapes are polled).
        XCTAssertTrue(expectWallBadge(name: "Journey jar", badgeLabel: "Unknown, no checks logged"),
                      "fresh culture should show the explicit unknown badge")

        // Open its detail (tap the NavigationLink cell).
        openRow(named: "Journey jar")
        expect("detail.screen")

        // Feed: 2 taps, no quantities.
        tap("detail.log.feed")
        expect("feed.commit")
        tap("feed.commit")

        // Timeline shows the committed event immediately.
        XCTAssertTrue(expectText("Feed — amounts not recorded"),
                      "feed event should appear in the timeline at once")

        // Back to the wall: badge must have flipped from Unknown to Fed.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(expectWallBadge(name: "Journey jar", badgeLabel: "Fed 0 hours ago"),
                      "wall badge must update after logging a feed")
        XCTAssertFalse(expectWallBadge(name: "Journey jar", badgeLabel: "Unknown, no checks logged", timeout: 3),
                       "stale unknown badge should be gone")
    }

    /// Empty-state → sample culture → derived badge exactly as the pure
    /// RiseKit pin (Linux-pinned `Fed 14h · peaked`), then check the
    /// sample timeline rows exist.
    func testSampleCultureSeedsKnownBadge() throws {
        app.launch()
        expect("wall.empty")
        tap("wall.sample")

        XCTAssertTrue(expectWallBadge(name: "Sample starter",
                                      badgeLabel: "Fed 14 hours ago, observed peaked"),
                      "sample badge must match the RiseKit-pinned derivation (VoiceOver form)")

        openRow(named: "Sample starter")
        expect("detail.screen")
        XCTAssertTrue(expectText("Feed — 50 g flour + 50 g water"))
        XCTAssertTrue(expectText("Rise check — peaked"))
        XCTAssertTrue(expectText("Last feed: 14h ago"))
    }

    /// Append-only affordances: undo adds a matching discard (both rows
    /// stay), correct re-logs the latest event.
    func testUndoAndCorrectAppendInsteadOfEditing() throws {
        app.launch()
        createCultureNamed("Audit jar")
        openRow(named: "Audit jar")
        expect("detail.screen")

        // Feed 50g, then undo -> a discard row appears; the feed row stays.
        tap("detail.log.feed")
        app.textFields["feed.flour"].waitForExistence(timeout: 10)
        app.textFields["feed.flour"].tap()
        app.textFields["feed.flour"].typeText("50")
        tap("feed.commit")
        XCTAssertTrue(expectText("Feed — 50 g flour"))

        expect("detail.undo", timeout: 10)
        tap("detail.undo")
        XCTAssertTrue(expectText("Discard — 50 g removed"),
                      "undo must append a discard, not remove the feed")
        XCTAssertTrue(expectText("Feed — 50 g flour"),
                      "the original feed row must remain (append-only)")

        // Correct the latest event: re-logged supersedes, original stays.
        tap("detail.correct")
        // confirmationDialog on iPhone presents as an action sheet, not
        // an alert — query the option button globally.
        let confirm = app.buttons["Log again now"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10),
                      "correct confirmation should offer 'Log again now'")
        confirm.tap()
        // Two identical discard rows now exist: the append-only trail keeps
        // the original while the correction supersedes it.
        let discards = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Discard — 50 g removed")
        )
        let deadline = Date().addingTimeInterval(15)
        while discards.count < 2 && Date() < deadline {
            app.swipeUp()
        }
        XCTAssertGreaterThanOrEqual(discards.count, 2,
                                    "correction must append a second row, not edit the first")
    }

    /// Same core loop at AX5 Dynamic Type, asserting the VoiceOver label
    /// (units spelled out) — the acceptance's accessibility gate, run on
    /// the simulator.
    func testCoreLoopAtAX5WithVoiceOverLabels() throws {
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibility5",
        ]
        app.launch()

        createCultureNamed("Big jar")
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Big jar")).firstMatch.tap()
        expect("detail.screen")

        tap("detail.log.feed")
        tap("feed.commit")
        // Back to the wall with large chrome: navigation back button is
        // still the first nav-bar button.
        app.navigationBars.buttons.firstMatch.tap()

        // Visible badge at AX5 + VoiceOver label form (units spelled out)
        // — the acceptance's accessibility gate, asserted on the wall row.
        XCTAssertTrue(expectWallBadge(name: "Big jar", badgeLabel: "Fed 0 hours ago",
                                      timeout: 25),
                      "badge (VoiceOver label form) must exist at AX5")
    }
}
