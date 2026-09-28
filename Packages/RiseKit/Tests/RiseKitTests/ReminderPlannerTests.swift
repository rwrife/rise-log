import Foundation
import Testing

@testable import RiseKit

@Suite("Local feeding reminder planning")
struct ReminderPlannerTests {
    private let anchor = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("off by default produces no requests")
    func offByDefault() {
        let culture = Culture(
            id: CultureID(rawValue: "mother"),
            name: "Mother Dough",
            type: .starter,
            createdAt: anchor
        )

        #expect(ReminderPlanner.plan(for: culture, lastFeedAt: anchor, now: anchor).isEmpty)
    }

    @Test("no logged feed produces no guessed anchor")
    func noFeedNoSchedule() throws {
        let cadence = try #require(FeedingCadence(everyHours: 24))
        let culture = Culture(
            id: CultureID(rawValue: "mother"),
            name: "Mother Dough",
            type: .starter,
            cadence: cadence,
            createdAt: anchor
        )

        #expect(ReminderPlanner.plan(for: culture, lastFeedAt: nil, now: anchor).isEmpty)
    }

    @Test("schedule uses the actual feed as its stable cadence anchor")
    func feedAnchorsCadence() throws {
        let cadence = try #require(FeedingCadence(everyHours: 12))
        let culture = Culture(
            id: CultureID(rawValue: "mother"),
            name: "Mother Dough",
            type: .starter,
            cadence: cadence,
            createdAt: anchor
        )

        let plan = ReminderPlanner.plan(
            for: culture,
            lastFeedAt: anchor,
            now: anchor.addingTimeInterval(60),
            occurrenceCount: 3
        )

        #expect(plan.map(\.fireAt) == [12, 24, 36].map { anchor.addingTimeInterval(Double($0) * 3_600) })
        #expect(plan.map(\.identifier) == [
            "riselog.feed.mother.0", "riselog.feed.mother.1", "riselog.feed.mother.2",
        ])
        #expect(plan.allSatisfy { $0.title == "Feeding reminder" })
        #expect(plan.allSatisfy { $0.body == "Log a feed for Mother Dough" })
    }

    @Test("past intervals roll forward on the original anchor without wall-clock drift")
    func rollsForwardFromAnchor() throws {
        let cadence = try #require(FeedingCadence(everyHours: 24))
        let culture = Culture(
            id: CultureID(rawValue: "rye"),
            name: "Rye",
            type: .starter,
            cadence: cadence,
            createdAt: anchor
        )
        let now = anchor.addingTimeInterval(49 * 3_600)

        let plan = ReminderPlanner.plan(for: culture, lastFeedAt: anchor, now: now, occurrenceCount: 2)

        #expect(plan.map(\.fireAt) == [72, 96].map { anchor.addingTimeInterval(Double($0) * 3_600) })
    }

    @Test("a new feed re-anchors every pending occurrence")
    func newFeedReanchors() throws {
        let cadence = try #require(FeedingCadence(everyHours: 168))
        let culture = Culture(
            id: CultureID(rawValue: "weekly"),
            name: "Weekly jar",
            type: .starter,
            cadence: cadence,
            createdAt: anchor
        )
        let newFeed = anchor.addingTimeInterval(3 * 86_400)

        let plan = ReminderPlanner.plan(for: culture, lastFeedAt: newFeed, now: newFeed, occurrenceCount: 1)

        #expect(plan.first?.fireAt == newFeed.addingTimeInterval(7 * 86_400))
    }

    @Test("cancellation prefix is scoped to one culture")
    func cancellationPrefix() {
        #expect(ReminderPlanner.identifierPrefix(for: CultureID(rawValue: "jar-a")) == "riselog.feed.jar-a.")
        #expect(ReminderPlanner.identifierPrefix(for: CultureID(rawValue: "jar-a"))
                != ReminderPlanner.identifierPrefix(for: CultureID(rawValue: "jar-b")))
    }
}
