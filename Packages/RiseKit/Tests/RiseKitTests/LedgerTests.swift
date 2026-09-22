import Foundation
import Testing

@testable import RiseKit

@Suite("Append-only ledger invariants")
struct LedgerTests {
    let d = TestFixtures.date(TestFixtures.utc, 2026, 4, 1, 12)

    @Test("duplicate event ids are rejected")
    func duplicateIds() {
        var ledger = EventLedger()
        let event = TestFixtures.feed("dup", at: d)
        #expect(throws: Never.self) { try ledger.append(event) }
        #expect(throws: RiseLogError.duplicateEventID(EventID(rawValue: "dup"))) {
            try ledger.append(event)
        }
        // Same id with different payload is still a duplicate id.
        #expect(throws: RiseLogError.duplicateEventID(EventID(rawValue: "dup"))) {
            try ledger.append(TestFixtures.event("dup", kind: .note, at: d, payload: .note("hijack")))
        }
        #expect(ledger.count == 1)
    }

    @Test("kind/payload mismatch is rejected")
    func payloadKindMismatch() {
        var ledger = EventLedger()
        #expect(throws: RiseLogError.payloadKindMismatch(eventId: EventID(rawValue: "bad"))) {
            try ledger.append(Event(
                id: EventID(rawValue: "bad"), cultureId: CultureID(rawValue: "c1"),
                kind: .feed, occurredAt: d, payload: .note("not a feed")))
        }
        #expect(ledger.count == 0)
    }

    @Test("all seven event kinds round-trip through append with matching payloads")
    func allKindsAccepted() throws {
        var ledger = EventLedger()
        let parent = CultureID(rawValue: "c0")
        let cases: [(Event.Kind, EventPayload)] = [
            (.feed, .feed(FeedAmount(flourGrams: 50, waterGrams: 50))),
            (.riseCheck, .riseCheck(.rising)),
            (.bottle, .bottle),
            (.bake, .bake(flourUsedGrams: 100)),
            (.discard, .discard(removedGrams: 25)),
            (.note, .note("smells tangy")),
            (.split, .split(parent: parent, separatedAt: d)),
        ]
        for (i, (kind, payload)) in cases.enumerated() {
            try ledger.append(TestFixtures.event("e\(i)", kind: kind, at: d, payload: payload))
        }
        #expect(ledger.count == 7)
        for (i, (kind, _)) in cases.enumerated() {
            let stored = ledger.event(withId: EventID(rawValue: "e\(i)"))
            #expect(stored?.kind == kind)
        }
    }

    @Test("events(for:) returns occurredAt order with deterministic tiebreak")
    func ordering() throws {
        var ledger = EventLedger()
        let early = TestFixtures.date(TestFixtures.utc, 2026, 4, 1, 8)
        let late = TestFixtures.date(TestFixtures.utc, 2026, 4, 1, 20)
        // Append out of order: late first.
        try ledger.append(TestFixtures.feed("b", at: late))
        try ledger.append(TestFixtures.feed("a", at: early))
        // Same timestamp: id tiebreak ("x" < "y").
        try ledger.append(TestFixtures.event("y", kind: .note, at: early, payload: .note("y")))
        try ledger.append(TestFixtures.event("x", kind: .note, at: early, payload: .note("x")))

        let ordered = ledger.events(for: CultureID(rawValue: "c1")).map(\.id.rawValue)
        #expect(ordered == ["a", "x", "y", "b"])
        // Reading twice yields the same order (no hidden mutable state).
        #expect(ledger.events(for: CultureID(rawValue: "c1")).map(\.id.rawValue) == ordered)
    }

    @Test("ledger never mutates or removes stored events; reads are value copies")
    func appendOnly() throws {
        var ledger = EventLedger()
        let original = TestFixtures.feed("f", at: d, amounts: FeedAmount(flourGrams: 50, waterGrams: 50))
        try ledger.append(original)
        let snapshot = ledger.allEvents

        // Append more, then confirm the original is byte-identical to snapshot.
        try ledger.append(TestFixtures.event("n", kind: .note, at: d, payload: .note("later")))
        #expect(ledger.event(withId: EventID(rawValue: "f")) == snapshot.first)
        #expect(ledger.count == 2)

        // Mutating a local copy of the ledger cannot alter an existing one
        // (value semantics — the append-only ledger can't be shrunk through
        // an alias).
        var copy = ledger
        copy = EventLedger()
        #expect(copy.count == 0)
        #expect(ledger.count == 2)
    }

    @Test("events are scoped per culture")
    func cultureScoping() throws {
        var ledger = EventLedger()
        try ledger.append(TestFixtures.feed("f1", at: d, culture: "c1"))
        try ledger.append(TestFixtures.feed("f2", at: d, culture: "c2"))
        #expect(ledger.events(for: CultureID(rawValue: "c1")).map(\.id.rawValue) == ["f1"])
        #expect(ledger.events(for: CultureID(rawValue: "c2")).map(\.id.rawValue) == ["f2"])
        #expect(ledger.events(for: CultureID(rawValue: "c3")).isEmpty)
    }

    @Test("containsEvent / event(withId) reflect the appended set")
    func lookups() throws {
        var ledger = EventLedger()
        #expect(!ledger.containsEvent(withId: EventID(rawValue: "f")))
        try ledger.append(TestFixtures.feed("f", at: d))
        #expect(ledger.containsEvent(withId: EventID(rawValue: "f")))
        #expect(ledger.event(withId: EventID(rawValue: "nope")) == nil)
    }
}
