import Foundation
import Testing

@testable import RiseKit

@Suite("Backup archive and CSV codec (Issue #6)")
struct BackupCodecTests {
    @Test("BackupArchive encodes and decodes JSON losslessly")
    func jsonRoundTrip() throws {
        let calendar = TestFixtures.utc
        let now = TestFixtures.date(calendar, 2026, 9, 27, 12, 0)
        let culture = TestFixtures.culture(id: "c1", cadence: FeedingCadence(everyHours: 24, graceHours: 4), createdAt: now.addingTimeInterval(-86400))
        let event1 = TestFixtures.feed("e1", at: now.addingTimeInterval(-3600), culture: "c1", amounts: FeedAmount(flourGrams: 50, waterGrams: 50))
        let event2 = Event(id: EventID(rawValue: "e2"), cultureId: CultureID(rawValue: "c1"), kind: .riseCheck, occurredAt: now.addingTimeInterval(-1800), payload: .riseCheck(.rising))

        let archive = BackupArchive(
            schemaVersion: 1,
            appVersion: "0.1.0",
            exportedAt: now,
            cultures: [culture],
            events: [(event: event1, loggedAt: now.addingTimeInterval(-3600)), (event: event2, loggedAt: now.addingTimeInterval(-1800))]
        )

        let data = try BackupCodec.encodeJSON(archive)
        #expect(!data.isEmpty)

        let decoded = try BackupCodec.decodeJSON(data)
        #expect(decoded.schemaVersion == 1)
        #expect(decoded.cultures.count == 1)
        #expect(decoded.cultures[0].id == culture.id)
        #expect(decoded.cultures[0].name == culture.name)
        #expect(decoded.cultures[0].cadence == culture.cadence)
        #expect(decoded.events.count == 2)
        #expect(decoded.events[0].event.id == event1.id)
        #expect(decoded.events[0].event.payload == event1.payload)
        #expect(decoded.events[1].event.id == event2.id)
        #expect(decoded.events[1].event.payload == event2.payload)
    }

    @Test("Unsupported schema version throws actionable error")
    func unsupportedSchemaVersion() {
        let json = """
        {
            "schema_version": 999,
            "app_version": "9.9.9",
            "exported_at": "2026-09-27T12:00:00.000Z",
            "cultures": [],
            "events": []
        }
        """.data(using: .utf8)!

        #expect(throws: BackupCodecError.self) {
            try BackupCodec.decodeJSON(json)
        }
    }

    @Test("Corrupt JSON throws corruptArchive error")
    func corruptJSON() {
        let corruptData = "{ this is not valid json }".data(using: .utf8)!
        #expect(throws: BackupCodecError.self) {
            try BackupCodec.decodeJSON(corruptData)
        }
    }

    @Test("CSV export formats event ledger accurately with RFC4180 escaping")
    func csvExport() throws {
        let calendar = TestFixtures.utc
        let now = TestFixtures.date(calendar, 2026, 9, 27, 12, 0)
        let culture = Culture(id: CultureID(rawValue: "c1"), name: "Starter, \"San Francisco\"", type: .starter, createdAt: now)
        let event1 = Event(id: EventID(rawValue: "e1"), cultureId: CultureID(rawValue: "c1"), kind: .feed, occurredAt: now, payload: .feed(FeedAmount(flourGrams: 50.5, waterGrams: 50)))
        let event2 = Event(id: EventID(rawValue: "e2"), cultureId: CultureID(rawValue: "c1"), kind: .note, occurredAt: now.addingTimeInterval(60), payload: .note("Smells fruity\nand sweet"))

        let csv = BackupCodec.exportCSV(
            cultures: [culture],
            events: [(event: event1, loggedAt: now), (event: event2, loggedAt: now.addingTimeInterval(60))]
        )

        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        #expect(lines.count == 3) // Header + 2 data rows
        #expect(lines[0].starts(with: "event_id,occurred_at,logged_at,culture_id,culture_name,kind,summary"))
        #expect(lines[1].contains("e1"))
        #expect(lines[1].contains("\"Starter, \"\"San Francisco\"\"\""))
        #expect(lines[2].contains("\"Smells fruity\nand sweet\""))
    }

    @Test("Preview replace computes accurate diff of added, removed, and kept entities")
    func previewReplace() {
        let calendar = TestFixtures.utc
        let now = TestFixtures.date(calendar, 2026, 9, 27, 12, 0)

        let cExisting1 = Culture(id: CultureID(rawValue: "c1"), name: "Rye", type: .starter, createdAt: now)
        let cExisting2 = Culture(id: CultureID(rawValue: "c2"), name: "Kombucha", type: .kombucha, createdAt: now)

        let eExisting1 = Event(id: EventID(rawValue: "e1"), cultureId: CultureID(rawValue: "c1"), kind: .feed, occurredAt: now, payload: .feed(.unspecified))

        let cArchive1 = Culture(id: CultureID(rawValue: "c1"), name: "Rye Starter", type: .starter, createdAt: now)
        let cArchive3 = Culture(id: CultureID(rawValue: "c3"), name: "Kimchi", type: .kimchi, createdAt: now)

        let eArchive1 = Event(id: EventID(rawValue: "e1"), cultureId: CultureID(rawValue: "c1"), kind: .feed, occurredAt: now, payload: .feed(.unspecified))
        let eArchive2 = Event(id: EventID(rawValue: "e2"), cultureId: CultureID(rawValue: "c3"), kind: .note, occurredAt: now, payload: .note("First ferment"))

        let archive = BackupArchive(
            schemaVersion: 1,
            appVersion: "0.1.0",
            exportedAt: now,
            cultures: [cArchive1, cArchive3],
            events: [(event: eArchive1, loggedAt: now), (event: eArchive2, loggedAt: now)]
        )

        let preview = BackupCodec.previewReplace(
            archive: archive,
            currentCultures: [cExisting1, cExisting2],
            currentEvents: [eExisting1]
        )

        #expect(preview.currentCultureCount == 2)
        #expect(preview.incomingCultureCount == 2)
        #expect(preview.addedCultureNames == ["Kimchi"])
        #expect(preview.removedCultureNames == ["Kombucha"])
        #expect(preview.keptCultureNames == ["Rye Starter"])
        #expect(preview.currentEventCount == 1)
        #expect(preview.incomingEventCount == 2)
        #expect(preview.addedEventCount == 1) // e2 is added
        #expect(preview.removedEventCount == 0) // e1 is in both
    }
}
