import Foundation
import Testing

@testable import RiseKit

@Suite("Backup store restore semantics (Issue #6)")
struct BackupStoreRoundTripTests {
    private let calendar = TestFixtures.utc

    @Test("export then replace-restore preserves exact store and derived state")
    func roundTripPreservesDerivedState() throws {
        let store = try RiseLogStore()
        let now = TestFixtures.date(calendar, 2026, 9, 27, 18, 0)
        let culture = Culture(
            id: CultureID(rawValue: "c1"),
            name: "Rye Starter",
            type: .starter,
            cadence: FeedingCadence(everyHours: 24, graceHours: 4),
            createdAt: now.addingTimeInterval(-4 * 86400)
        )
        let event1 = Event(
            id: EventID(rawValue: "e1"),
            cultureId: culture.id,
            kind: .feed,
            occurredAt: now.addingTimeInterval(-8 * 3600),
            payload: .feed(FeedAmount(flourGrams: 75, waterGrams: 75))
        )
        let event2 = Event(
            id: EventID(rawValue: "e2"),
            cultureId: culture.id,
            kind: .riseCheck,
            occurredAt: now.addingTimeInterval(-2 * 3600),
            payload: .riseCheck(.rising)
        )

        try store.saveCulture(culture)
        try store.insertEvent(event1, loggedAt: now.addingTimeInterval(-8 * 3600))
        try store.insertEvent(event2, loggedAt: now.addingTimeInterval(-2 * 3600))

        let engine = StatusEngine(calendar: calendar)
        let beforeCultures = try store.allCultures()
        let beforeEvents = try store.allEventsWithLoggedAt()
        let beforeStatus = engine.status(for: culture, ledger: try store.ledgerSnapshot(), now: now)

        let archive = try store.exportArchive(appVersion: "0.1.0-test")
        let encoded = try BackupCodec.encodeJSON(archive)
        let decoded = try BackupCodec.decodeJSON(encoded)

        // "Wipe store" by replacing with an empty valid archive.
        let empty = BackupArchive(appVersion: "0.1.0-test", exportedAt: now, cultures: [], events: [])
        try store.restoreReplacingAllData(from: empty)
        #expect(try store.allCultures().isEmpty)
        #expect(try store.allEvents().isEmpty)

        try store.restoreReplacingAllData(from: decoded)

        let afterCultures = try store.allCultures()
        let afterEvents = try store.allEventsWithLoggedAt()
        let afterStatus = engine.status(for: culture, ledger: try store.ledgerSnapshot(), now: now)

        #expect(afterCultures == beforeCultures)
        #expect(afterEvents.count == beforeEvents.count)
        for index in afterEvents.indices {
            #expect(afterEvents[index].event == beforeEvents[index].event)
            #expect(abs(afterEvents[index].loggedAt.timeIntervalSince(beforeEvents[index].loggedAt)) < 0.001)
        }
        #expect(afterStatus == beforeStatus)
    }

    @Test("incompatible fixture leaves current store untouched")
    func incompatibleFixtureLeavesStoreUntouched() throws {
        let store = try seededStore()
        let beforeCultures = try store.allCultures()
        let beforeEvents = try store.allEventsWithLoggedAt()

        let data = try fixtureData(named: "incompatible")
        #expect(throws: BackupCodecError.self) {
            let archive = try BackupCodec.decodeJSON(data)
            try store.restoreReplacingAllData(from: archive)
        }

        #expect(try store.allCultures() == beforeCultures)
        #expect(try store.allEventsWithLoggedAt().map(\.event) == beforeEvents.map(\.event))
    }

    @Test("corrupt fixture leaves current store untouched")
    func corruptFixtureLeavesStoreUntouched() throws {
        let store = try seededStore()
        let beforeCultures = try store.allCultures()
        let beforeEvents = try store.allEventsWithLoggedAt()

        let data = try fixtureData(named: "corrupt")
        #expect(throws: BackupCodecError.self) {
            let archive = try BackupCodec.decodeJSON(data)
            try store.restoreReplacingAllData(from: archive)
        }

        #expect(try store.allCultures() == beforeCultures)
        #expect(try store.allEventsWithLoggedAt().map(\.event) == beforeEvents.map(\.event))
    }

    @Test("failed atomic restore rolls back replacement and keeps append-only triggers")
    func failedRestoreRollsBack() throws {
        let store = try seededStore()
        let beforeCultures = try store.allCultures()
        let beforeEvents = try store.allEvents()
        let now = TestFixtures.date(calendar, 2026, 9, 27, 18, 0)

        // Duplicate culture IDs pass the basic reference validation but fail on PK insert
        // after the delete phase has started, proving transaction rollback restores old data.
        let duplicateA = Culture(id: CultureID(rawValue: "dup"), name: "A", type: .starter, createdAt: now)
        let duplicateB = Culture(id: CultureID(rawValue: "dup"), name: "B", type: .kombucha, createdAt: now)
        let badArchive = BackupArchive(appVersion: "test", exportedAt: now, cultures: [duplicateA, duplicateB], events: [])

        #expect(throws: (any Error).self) {
            try store.restoreReplacingAllData(from: badArchive)
        }
        #expect(try store.allCultures() == beforeCultures)
        #expect(try store.allEvents() == beforeEvents)

        // Original append-only database trigger must still exist after rollback.
        #expect(throws: (any Error).self) {
            try store.write { db in
                try db.execute(sql: "DELETE FROM event")
            }
        }
    }

    private func seededStore() throws -> RiseLogStore {
        let store = try RiseLogStore()
        let now = TestFixtures.date(calendar, 2026, 9, 27, 18, 0)
        let culture = Culture(id: CultureID(rawValue: "seed"), name: "Seed", type: .starter, createdAt: now)
        let event = Event(
            id: EventID(rawValue: "seed-event"),
            cultureId: culture.id,
            kind: .note,
            occurredAt: now,
            payload: .note("Existing data")
        )
        try store.saveCulture(culture)
        try store.insertEvent(event, loggedAt: now)
        return store
    }

    private func fixtureData(named name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw BackupCodecError.corruptArchive("Missing test fixture \(name).json")
        }
        return try Data(contentsOf: url)
    }
}
