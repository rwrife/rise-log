import Foundation
import Testing

@testable import RiseKit

/// The sample culture's event set must deterministically produce a known
/// badge — this is what the onboarding journey asserts on simulator CI,
/// pinned here on Linux.
@Suite("Sample data determinism")
struct SampleDataTests {
    @Test("sample seeds a culture whose badge is exactly 'Fed 14h · peaked'")
    func sampleBadge() throws {
        let anchor = TestFixtures.date(TestFixtures.utc, 2026, 3, 10, 12)
        let culture = SampleData.culture(anchor: anchor, calendar: TestFixtures.utc)
        var ledger = EventLedger()
        for event in SampleData.events(anchor: anchor, calendar: TestFixtures.utc) {
            try ledger.append(event)
        }
        let engine = StatusEngine(calendar: TestFixtures.utc)
        let status = engine.status(for: culture, ledger: ledger, now: anchor)
        #expect(status.badgeText == "Fed 14h · peaked")
        #expect(status.lastFeedLineText == "Last feed: 14h ago")
        #expect(status.risePhaseLineText == "Rise phase: peaked")
    }

    @Test("sample seeds through the store without validation errors")
    func sampleThroughStore() throws {
        let store = try RiseLogStore()
        let anchor = TestFixtures.date(TestFixtures.utc, 2026, 3, 10, 12)
        try SampleData.seed(into: store, anchor: anchor, calendar: TestFixtures.utc)
        let cultures = try store.allCultures()
        #expect(cultures.count == 1)
        #expect(cultures.first?.name == SampleData.cultureName)
        let events = try store.events(for: SampleData.cultureID)
        #expect(events.count == 4)
        // Append-only check: re-seeding fails on duplicate ids, not half-writes.
        #expect(throws: (any Error).self) {
            try SampleData.seed(into: store, anchor: anchor, calendar: TestFixtures.utc)
        }
    }
}

/// `Event.displaySummary` is the timeline text the UI shows verbatim.
@Suite("Event display summaries")
struct DisplaySummaryTests {
    @Test("each kind renders its one-line summary")
    func summaries() {
        let t = TestFixtures.date(TestFixtures.utc, 2026, 3, 10, 12)
        func event(_ kind: Event.Kind, _ payload: EventPayload) -> Event {
            TestFixtures.event("e", kind: kind, at: t, payload: payload)
        }
        #expect(event(.feed, .feed(FeedAmount(flourGrams: 50, waterGrams: 50)))
                .displaySummary == "Feed — 50 g flour + 50 g water")
        #expect(event(.feed, .feed(FeedAmount(flourGrams: 50, waterGrams: nil)))
                .displaySummary == "Feed — 50 g flour")
        #expect(event(.feed, .feed(.unspecified))
                .displaySummary == "Feed — amounts not recorded")
        #expect(event(.feed, .feed(FeedAmount(flourGrams: 37.5, waterGrams: 37.5)))
                .displaySummary == "Feed — 37.5 g flour + 37.5 g water")
        #expect(event(.riseCheck, .riseCheck(.peaked))
                .displaySummary == "Rise check — peaked")
        #expect(event(.bottle, .bottle).displaySummary == "Bottle")
        #expect(event(.bake, .bake(flourUsedGrams: 200))
                .displaySummary == "Bake — 200 g flour used")
        #expect(event(.discard, .discard(removedGrams: nil))
                .displaySummary == "Discard — amount not recorded")
        #expect(event(.note, .note("smells tangy, happy jar"))
                .displaySummary == "Note — smells tangy, happy jar")
    }
}
