import Foundation
import Testing
import GRDB
@testable import RiseKit

/// Fixture helpers for store tests (dates use whole seconds to stay exact
/// under GRDB's `.datetime` storage; `loggedAt` values are explicit for
/// deterministic tiebreak tests).
private enum StoreFixtures {
    static func culture(
        id: String = "c1",
        name: String = "Test jar",
        type: CultureType = .starter,
        cadence: FeedingCadence? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> Culture {
        Culture(id: CultureID(rawValue: id), name: name, type: type,
                cadence: cadence, createdAt: createdAt)
    }

    static func event(
        _ id: String,
        culture: String = "c1",
        kind: Event.Kind,
        occurredAt: Date,
        payload: EventPayload = .feed(.unspecified)
    ) -> Event {
        Event(id: EventID(rawValue: id), cultureId: CultureID(rawValue: culture),
              kind: kind, occurredAt: occurredAt, payload: payload)
    }

    static let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    static let t1 = Date(timeIntervalSince1970: 1_700_003_600)
    static let t2 = Date(timeIntervalSince1970: 1_700_007_200)
}

@Suite("Store: migrations")
struct StoreMigrationTests {
    @Test("fresh database migrates to migration 1")
    func freshMigration() throws {
        let store = try RiseLogStore()
        #expect(try store.currentSchemaVersion() == "v1-initial")
        try store.write { db in
            let hasCulture: Bool = try db.tableExists("culture")
            let hasEvent: Bool = try db.tableExists("event")
            let hasEdge: Bool = try db.tableExists("lineage_edge")
            #expect(hasCulture && hasEvent && hasEdge)
        }
    }

    @Test("migration-1 replay is reproducible: drop everything, re-run, schema matches")
    func migrationReplayReproducibility() throws {
        let store = try RiseLogStore()

        // Snapshot the freshly-migrated schema (tables, columns, triggers,
        // indexes) from sqlite_master, canonicalized.
        func schema(_ db: Database) throws -> [String] {
            try String.fetchAll(
                db,
                sql: """
                    SELECT sql FROM sqlite_master
                    WHERE sql IS NOT NULL
                    ORDER BY type, name
                    """)
        }
        let first = try store.write { try schema($0) }
        #expect(!first.isEmpty)

        // Wipe the database and replay migration 1 through the same
        // migrator: the resulting schema must be byte-identical.
        try store.write { db in
            try db.execute(sql: "DROP TRIGGER lineage_edge_insert")
            try db.execute(sql: "DROP TRIGGER event_no_delete")
            try db.execute(sql: "DROP TRIGGER event_no_update")
            try db.execute(sql: "DROP TABLE lineage_edge")
            try db.execute(sql: "DROP TABLE event")
            try db.execute(sql: "DROP TABLE culture")
            try db.execute(sql: "DELETE FROM grdb_migrations")
        }
        try store.migrate()
        let second = try store.write { try schema($0) }
        #expect(second == first)
        #expect(try store.currentSchemaVersion() == "v1-initial")
    }

    @Test("relaunching a file store restores exact state")
    func relaunchRoundTrip() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("riselog-store-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let culture = StoreFixtures.culture(
            cadence: FeedingCadence(everyHours: 12, graceHours: 2))
        try RiseLogStore(url: url).saveCulture(culture)

        let reopened = try RiseLogStore(url: url)
        #expect(try reopened.culture(withId: CultureID(rawValue: "c1")) == culture)
        #expect(try reopened.currentSchemaVersion() == "v1-initial")
    }
}

@Suite("Store: cultures")
struct StoreCultureTests {
    @Test("all predefined culture types round-trip")
    func predefinedRoundTrip() throws {
        let store = try RiseLogStore()
        for p in PredefinedCultureType.allCases {
            let c = StoreFixtures.culture(id: "c-\(p.rawValue)", type: .init(kind: .predefined(p)))
            try store.saveCulture(c)
            #expect(try store.culture(withId: c.id) == c)
        }
    }

    @Test("custom culture type round-trips")
    func customRoundTrip() throws {
        let store = try RiseLogStore()
        guard let type = CultureType(customName: "Ginger bug") else {
            Issue.record("fixture type rejected"); return
        }
        let c = StoreFixtures.culture(id: "gb", name: "Bug jar", type: type)
        try store.saveCulture(c)
        let loaded = try store.culture(withId: c.id)
        #expect(loaded == c)
        if case .custom(let label)? = loaded?.type.kind {
            #expect(label == "Ginger bug")
        } else {
            Issue.record("custom kind lost")
        }
    }

    @Test("cadence round-trips; absent cadence stays absent")
    func cadenceRoundTrip() throws {
        let store = try RiseLogStore()
        let withCadence = StoreFixtures.culture(id: "a", cadence: FeedingCadence(everyHours: 24, graceHours: 6))
        let without = StoreFixtures.culture(id: "b")
        try store.saveCulture(withCadence)
        try store.saveCulture(without)
        #expect(try store.culture(withId: withCadence.id) == withCadence)
        #expect(try store.culture(withId: without.id) == without)
    }

    @Test("culture edits (rename / cadence) replace the row; unknown cultures read nil")
    func cultureEdits() throws {
        let store = try RiseLogStore()
        var c = StoreFixtures.culture()
        try store.saveCulture(c)
        c.name = "Renamed jar"
        c.cadence = FeedingCadence(everyHours: 8, graceHours: 1)
        try store.saveCulture(c)
        #expect(try store.culture(withId: c.id) == c)
        #expect(try store.allCultures() == [c])
        #expect(try store.culture(withId: CultureID(rawValue: "nope")) == nil)
    }

    @Test("blank custom type label is impossible at the domain boundary")
    func blankCustomRejectedAtDomain() {
        #expect(CultureType(customName: "   ") == nil)
    }

    @Test("allCultures orders by name with id tiebreak")
    func cultureOrder() throws {
        let store = try RiseLogStore()
        try store.saveCulture(StoreFixtures.culture(id: "z", name: "Alpha"))
        try store.saveCulture(StoreFixtures.culture(id: "a", name: "Alpha"))
        try store.saveCulture(StoreFixtures.culture(id: "m", name: "Beta"))
        let ids = try store.allCultures().map(\.id.rawValue)
        #expect(ids == ["a", "z", "m"])
    }
}

@Suite("Store: append-only events")
struct StoreEventTests {
    @Test("all event kinds and payload shapes round-trip through the store")
    func eventRoundTrip() throws {
        let store = try RiseLogStore()
        try store.saveCulture(StoreFixtures.culture())
        try store.saveCulture(StoreFixtures.culture(id: "c2", name: "Parent"))

        let events: [Event] = [
            StoreFixtures.event("e1", kind: .feed, occurredAt: StoreFixtures.t0,
                                payload: .feed(FeedAmount(flourGrams: 20, waterGrams: 20))),
            StoreFixtures.event("e2", kind: .feed, occurredAt: StoreFixtures.t1),
            StoreFixtures.event("e3", kind: .riseCheck, occurredAt: StoreFixtures.t2,
                                payload: .riseCheck(.peaked)),
            StoreFixtures.event("e4", kind: .bottle, occurredAt: StoreFixtures.t2,
                                payload: .bottle),
            StoreFixtures.event("e5", kind: .bake, occurredAt: StoreFixtures.t2,
                                payload: .bake(flourUsedGrams: 450)),
            StoreFixtures.event("e6", kind: .discard, occurredAt: StoreFixtures.t2,
                                payload: .discard(removedGrams: 50)),
            StoreFixtures.event("e7", kind: .note, occurredAt: StoreFixtures.t2,
                                payload: .note("smells tangy")),
            StoreFixtures.event("e8", kind: .note, occurredAt: StoreFixtures.t2,
                                payload: .note("")),
            StoreFixtures.event("e9", culture: "c1", kind: .split, occurredAt: StoreFixtures.t2,
                                payload: .split(parent: CultureID(rawValue: "c2"),
                                                separatedAt: StoreFixtures.t1)),
        ]
        for (i, e) in events.enumerated() {
            try store.insertEvent(e, loggedAt: StoreFixtures.t0.addingTimeInterval(Double(i)))
        }
        for e in events {
            #expect(try store.event(withId: e.id) == e)
        }
        let timeline = try store.events(for: CultureID(rawValue: "c1"))
        #expect(Set(timeline.map(\.id)) == Set(events.filter { $0.cultureId.rawValue == "c1" }.map(\.id)))
        #expect(try store.allEvents().count == events.count)
    }

    @Test("duplicate event id is rejected without touching the ledger")
    func duplicateRejected() throws {
        let store = try RiseLogStore()
        try store.saveCulture(StoreFixtures.culture())
        let e = StoreFixtures.event("dup", kind: .feed, occurredAt: StoreFixtures.t0)
        try store.insertEvent(e, loggedAt: StoreFixtures.t0)
        #expect(throws: RiseLogError.duplicateEventID(EventID(rawValue: "dup"))) {
            try store.insertEvent(e, loggedAt: StoreFixtures.t1)
        }
        // Still exactly one row with the original loggedAt.
        let timeline = try store.events(for: CultureID(rawValue: "c1"))
        #expect(timeline.count == 1)
    }

    @Test("kind/payload disagreement is rejected (same rules as EventLedger)")
    func payloadMismatchRejected() throws {
        let store = try RiseLogStore()
        try store.saveCulture(StoreFixtures.culture())
        let mismatch = Event(id: EventID(rawValue: "bad"),
                             cultureId: CultureID(rawValue: "c1"),
                             kind: .feed, occurredAt: StoreFixtures.t0,
                             payload: .note("not a feed"))
        #expect(throws: RiseLogError.payloadKindMismatch(eventId: EventID(rawValue: "bad"))) {
            try store.insertEvent(mismatch, loggedAt: StoreFixtures.t0)
        }
        let nilNote = Event(id: EventID(rawValue: "bad2"),
                            cultureId: CultureID(rawValue: "c1"),
                            kind: .note, occurredAt: StoreFixtures.t0,
                            payload: .feed(.unspecified))
        #expect(throws: RiseLogError.payloadKindMismatch(eventId: EventID(rawValue: "bad2"))) {
            try store.insertEvent(nilNote, loggedAt: StoreFixtures.t0)
        }
    }

    @Test("events referencing unknown cultures or split parents are rejected")
    func unknownReferencesRejected() throws {
        let store = try RiseLogStore()
        let orphan = StoreFixtures.event("o1", kind: .feed, occurredAt: StoreFixtures.t0)
        #expect(throws: RiseLogError.unknownCulture(CultureID(rawValue: "c1"))) {
            try store.insertEvent(orphan, loggedAt: StoreFixtures.t0)
        }
        try store.saveCulture(StoreFixtures.culture())
        let badSplit = StoreFixtures.event("o2", kind: .split, occurredAt: StoreFixtures.t0,
                                           payload: .split(parent: CultureID(rawValue: "ghost"),
                                                           separatedAt: StoreFixtures.t1))
        #expect(throws: RiseLogError.unknownParent(CultureID(rawValue: "ghost"))) {
            try store.insertEvent(badSplit, loggedAt: StoreFixtures.t0)
        }
    }

    @Test("SQL UPDATE and DELETE on event are rejected by append-only triggers")
    func appendOnlyTriggers() throws {
        let store = try RiseLogStore()
        try store.saveCulture(StoreFixtures.culture())
        let e = StoreFixtures.event("locked", kind: .feed, occurredAt: StoreFixtures.t0,
                                    payload: .feed(FeedAmount(flourGrams: 10, waterGrams: 10)))
        try store.insertEvent(e, loggedAt: StoreFixtures.t0)

        #expect(throws: (any Error).self) {
            try store.write { db in
                try db.execute(sql: "UPDATE event SET flourGrams = 9999 WHERE id = 'locked'")
            }
        }
        #expect(throws: (any Error).self) {
            try store.write { db in
                try db.execute(sql: "DELETE FROM event WHERE id = 'locked'")
            }
        }
        // The stored payload survived the attempted tampering.
        let loaded = try store.event(withId: EventID(rawValue: "locked"))
        #expect(loaded == e)
    }

    @Test("timeline orders by occurredAt then loggedAt then id (deterministic ties)")
    func timelineOrder() throws {
        let store = try RiseLogStore()
        try store.saveCulture(StoreFixtures.culture())
        // Same occurredAt for three events, distinct loggedAt + one equal.
        try store.insertEvent(StoreFixtures.event("b", kind: .feed, occurredAt: StoreFixtures.t0),
                              loggedAt: StoreFixtures.t1)
        try store.insertEvent(StoreFixtures.event("a", kind: .feed, occurredAt: StoreFixtures.t0),
                              loggedAt: StoreFixtures.t1)
        try store.insertEvent(StoreFixtures.event("c", kind: .feed, occurredAt: StoreFixtures.t0),
                              loggedAt: StoreFixtures.t0)
        try store.insertEvent(StoreFixtures.event("z", kind: .feed, occurredAt: StoreFixtures.t2),
                              loggedAt: StoreFixtures.t2)
        let ids = try store.events(for: CultureID(rawValue: "c1")).map(\.id.rawValue)
        #expect(ids == ["c", "a", "b", "z"])
    }

    @Test("store timeline matches EventLedger ordering when loggedAt mirrors insertion")
    func timelineMatchesLedger() throws {
        let store = try RiseLogStore()
        try store.saveCulture(StoreFixtures.culture())
        var ledger = EventLedger()
        // Insert in id-sorted order with monotonic loggedAt: occurredAt
        // ties then resolve identically in both systems (store: loggedAt
        // then id; ledger: id), so both timelines must agree.
        var clock = StoreFixtures.t0
        for id in ["j", "k", "m", "q"] {
            let e = StoreFixtures.event(id, kind: .feed,
                occurredAt: id == "q" ? StoreFixtures.t2 : StoreFixtures.t0)
            clock = clock.addingTimeInterval(1)
            try store.insertEvent(e, loggedAt: clock)
            try ledger.append(e)
        }
        let storeIds = try store.events(for: CultureID(rawValue: "c1")).map(\.id.rawValue)
        let ledgerIds = ledger.events(for: CultureID(rawValue: "c1")).map(\.id.rawValue)
        #expect(storeIds == ledgerIds)
    }

    @Test("lastFeed returns the most recent feed only; nil when no feed")
    func lastFeedQuery() throws {
        let store = try RiseLogStore()
        try store.saveCulture(StoreFixtures.culture())
        try store.saveCulture(StoreFixtures.culture(id: "empty", name: "Quiet jar"))

        try store.insertEvent(StoreFixtures.event("f1", kind: .feed, occurredAt: StoreFixtures.t0),
                              loggedAt: StoreFixtures.t0)
        try store.insertEvent(StoreFixtures.event("n1", kind: .note, occurredAt: StoreFixtures.t2,
                                                  payload: .note("later note")),
                              loggedAt: StoreFixtures.t2)
        let last = try store.lastFeed(for: CultureID(rawValue: "c1"))
        #expect(last?.id == EventID(rawValue: "f1"))

        #expect(try store.lastFeed(for: CultureID(rawValue: "empty")) == nil)

        // A back-dated feed doesn't dethrone the newer one.
        try store.insertEvent(StoreFixtures.event("f0", kind: .feed, occurredAt: StoreFixtures.t0.addingTimeInterval(-100)),
                              loggedAt: StoreFixtures.t2)
        #expect(try store.lastFeed(for: CultureID(rawValue: "c1"))?.id == EventID(rawValue: "f1"))
    }
}

@Suite("Store: lineage edges + snapshot")
struct StoreLineageTests {
    @Test("split events materialize lineage edges")
    func edgesFromSplits() throws {
        let store = try RiseLogStore()
        try store.saveCulture(StoreFixtures.culture(id: "p", name: "Mother"))
        try store.saveCulture(StoreFixtures.culture(id: "ch", name: "Child"))
        let split = StoreFixtures.event("s1", culture: "ch", kind: .split,
                                        occurredAt: StoreFixtures.t0,
                                        payload: .split(parent: CultureID(rawValue: "p"),
                                                        separatedAt: StoreFixtures.t1))
        try store.insertEvent(split, loggedAt: StoreFixtures.t0)

        let edges = try store.lineageEdges()
        #expect(edges.count == 1)
        #expect(edges[0].parent == CultureID(rawValue: "p"))
        #expect(edges[0].child == CultureID(rawValue: "ch"))
        #expect(edges[0].separatedAt == StoreFixtures.t1)

        // The materialized edges replay losslessly into the pure graph.
        let graph = try LineageGraph.build(from: store.ledgerSnapshot(),
                                          knownCultureIds: [CultureID(rawValue: "p"),
                                                            CultureID(rawValue: "ch")])
        #expect(graph.children(of: CultureID(rawValue: "p")) == [CultureID(rawValue: "ch")])
        #expect(graph.parents(of: CultureID(rawValue: "ch")) == [CultureID(rawValue: "p")])
    }

    @Test("ledgerSnapshot feeds StatusEngine-derived reads with exact events")
    func snapshotMatchesStore() throws {
        let store = try RiseLogStore()
        try store.saveCulture(StoreFixtures.culture())
        let events = [
            StoreFixtures.event("s-a", kind: .feed, occurredAt: StoreFixtures.t0),
            StoreFixtures.event("s-b", kind: .riseCheck, occurredAt: StoreFixtures.t1,
                                payload: .riseCheck(.rising)),
        ]
        for (i, e) in events.enumerated() {
            try store.insertEvent(e, loggedAt: StoreFixtures.t0.addingTimeInterval(Double(i)))
        }
        let snap = try store.ledgerSnapshot()
        #expect(snap.count == 2)
        #expect(Set(snap.allEvents) == Set(events))
    }
}
