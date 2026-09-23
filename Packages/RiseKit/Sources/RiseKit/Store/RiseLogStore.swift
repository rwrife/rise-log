import Foundation
import GRDB

/// Errors surfaced by store operations.
public enum StoreError: Error, Equatable, Sendable {
    /// The referenced culture does not exist.
    case unknownCulture(CultureID)
    /// The referenced event does not exist.
    case unknownEvent(EventID)
    /// An insert would violate append-only invariants (event id already
    /// present, or a raw UPDATE/DELETE tried against the `event` table —
    /// rejected by database triggers, mirroring `EventLedger` semantics).
    case appendOnlyViolation(String)
}

/// The durable local store (issue #3): GRDB/SQLite schema, versioned
/// migrations, append-only event persistence, and indexed derived queries.
///
/// Truth split (PLAN.md): the `culture` table owns culture records; the
/// append-only `event` table owns the ledger; derived status stays in the
/// pure `StatusEngine` and is never stored here.
///
/// Timestamps: `occurredAt` — the ledger's ordering key — is stored in
/// `yyyy-MM-dd HH:mm:ss.SSS` UTC format. That format is lossy below the
/// millisecond, and GRDB's DATE comparison actually truncates to SECONDS,
/// so timeline ordering uses a deterministic tiebreak chain
/// `(occurredAt, loggedAt, id)`; the in-memory `EventLedger` tiebreak
/// (`id`) is preserved as the final key. `loggedAt` is the immutable
/// wall-clock insert stamp (full ms precision) used for audit ordering.
///
/// Append-only enforcement is defense-in-depth:
/// 1. SQL triggers reject `UPDATE` and `DELETE` on `event` (corrections are
///    new events or tombstone-linked, never silent payload edits).
/// 2. Repository API has no update/delete path for events at all.
/// 3. `insertEvent` validates kind/payload agreement up front via
///    `EventLedger` semantics before touching the database.
public final class RiseLogStore: Sendable {
    private let reader: any DatabaseReader
    private let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        self.reader = writer
        try migrate()
    }

    /// In-memory store for tests and transient sessions.
    public convenience init() throws {
        try self.init(DatabaseQueue())
    }

    /// Open (and migrate) a file-backed store.
    public convenience init(url: URL) throws {
        try self.init(DatabaseQueue(path: url.path))
    }

    /// Escape hatch for tests and later features: run raw SQL/record work
    /// in a write transaction.
    public func write<T>(_ block: @escaping (Database) throws -> T) throws -> T {
        try writer.write(block)
    }

    // MARK: - Migrations

    /// Registered migration identifiers, oldest first.
    public static let migrationIdentifiers = ["v1-initial"]

    /// The migration-1 schema, kept for the fresh-create test and for the
    /// sandbox/production path to share exactly one definition.
    static func migrator() -> DatabaseMigrator {
        var m = DatabaseMigrator()

        m.registerMigration("v1-initial") { db in
            // Cultures: one row per jar. Status is never stored.
            try db.create(table: "culture") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                // predefined XOR customName (CHECK below), both nullable
                // individually: exactly one must be set.
                t.column("predefined", .text)
                t.column("customName", .text)
                t.column("cadenceEveryHours", .integer)
                t.column("cadenceGraceHours", .integer)
                t.column("createdAt", .datetime).notNull()
                t.check(sql: """
                    (predefined IS NOT NULL AND customName IS NULL) OR
                    (predefined IS NULL AND customName IS NOT NULL AND customName <> '')
                    """)
            }

            // Events: append-only ledger. Corrections are NEW events (or
            // tombstone-linked in later slices) — never UPDATEs of stored
            // payloads, which the two triggers below make physically
            // impossible.
            try db.create(table: "event") { t in
                t.column("id", .text).primaryKey()
                t.column("cultureId", .text).notNull()
                    .references("culture", onDelete: .cascade)
                t.column("kind", .text).notNull()
                t.column("occurredAt", .datetime).notNull()
                // Immutable insert stamp (audit); full ms precision.
                t.column("loggedAt", .datetime).notNull()
                // Payload columns — see EventRecord for the kind ⇄ columns
                // bijection validated at the repository boundary.
                t.column("flourGrams", .double)
                t.column("waterGrams", .double)
                t.column("stage", .text)
                t.column("flourUsedGrams", .double)
                t.column("removedGrams", .double)
                t.column("noteText", .text)
                t.column("splitParentId", .text).references("culture", onDelete: .cascade)
                t.column("separatedAt", .datetime)
            }
            // Timeline + per-culture scans (last feed, ordered history).
            try db.create(index: "event_culture_occurred", on: "event",
                          columns: ["cultureId", "occurredAt", "loggedAt", "id"])

            // Append-only enforcement (acceptance: "no silent UPDATE of
            // event payloads"). RAISE(ABORT) fails the offending statement.
            try db.execute(sql: """
                CREATE TRIGGER event_no_update BEFORE UPDATE ON event
                BEGIN
                    SELECT RAISE(ABORT, 'event table is append-only: updates are rejected');
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER event_no_delete BEFORE DELETE ON event
                BEGIN
                    SELECT RAISE(ABORT, 'event table is append-only: deletes are rejected');
                END
                """)

            // Lineage edges materialized from split events (acceptance:
            // "lineage edges"). Kept in sync by triggers on the event
            // table so the edge set can never drift from the ledger.
            try db.create(table: "lineage_edge") { t in
                t.column("parentId", .text).notNull()
                    .references("culture", onDelete: .cascade)
                t.column("childId", .text).notNull()
                    .references("culture", onDelete: .cascade)
                t.column("separatedAt", .datetime).notNull()
                t.primaryKey(["parentId", "childId"])
            }
            try db.create(index: "lineage_edge_child", on: "lineage_edge", columns: ["childId"])
            try db.execute(sql: """
                CREATE TRIGGER lineage_edge_insert AFTER INSERT ON event
                WHEN NEW.kind = 'split' AND NEW.splitParentId IS NOT NULL
                BEGIN
                    INSERT OR REPLACE INTO lineage_edge (parentId, childId, separatedAt)
                    VALUES (NEW.splitParentId, NEW.cultureId, NEW.separatedAt);
                END
                """)
            // An edge survives an attempted culture cascade only while the
            // culture rows exist; cascade (ON DELETE) prunes both sides —
            // deletion of cultures is out of scope until the UI slice.
        }
        return m
    }

    /// Apply pending schema migrations.
    public func migrate() throws {
        try Self.migrator().migrate(writer)
    }

    /// Latest applied schema version (nil on an unmigrated database).
    public func currentSchemaVersion() throws -> String? {
        try reader.read { r in
            guard try r.tableExists("grdb_migrations") else { return nil }
            let applied = try String.fetchSet(
                r, sql: "SELECT identifier FROM grdb_migrations")
            return Self.migrationIdentifiers.last(where: applied.contains)
        }
    }

    // MARK: - Cultures

    /// Inserts or replaces a culture record (rename/cadence edits are the
    /// only mutations cultures ever get; the ledger itself is untouched).
    public func saveCulture(_ culture: Culture) throws {
        try writer.write { w in try CultureRecord(culture).save(w) }
    }

    public func culture(withId id: CultureID) throws -> Culture? {
        try reader.read { r in
            try CultureRecord.fetchOne(r, key: id.rawValue).map { $0.toDomain() }
        }
    }

    /// All cultures, ordered by name (stable: id tiebreak).
    public func allCultures() throws -> [Culture] {
        try reader.read { r in
            try CultureRecord
                .order(Column("name"), Column("id"))
                .fetchAll(r)
                .map { $0.toDomain() }
        }
    }

    // MARK: - Events (append-only)

    /// Appends one event to the ledger.
    ///
    /// Rejects (before touching SQLite):
    /// - an id already present (`RiseLogError.duplicateEventID`),
    /// - kind/payload disagreement (`RiseLogError.payloadKindMismatch`,
    ///   including `.note(nil)` which would be ambiguous in columns),
    /// - events referencing an unknown culture (`RiseLogError.unknownCulture`),
    /// - split events whose parent is unknown (`RiseLogError.unknownParent`).
    ///
    /// `loggedAt` defaults to now; tests and future replay paths pass it
    /// explicitly.
    public func insertEvent(_ event: Event, loggedAt: Date = Date()) throws {
        // Validate through the same in-memory ledger rules that issue #2
        // established as canonical: append into a throwaway ledger view
        // with the culture set from the DB. This keeps ONE definition of
        // ledger-valid in the codebase.
        try writer.write { w in
            let known = try Set(String.fetchAll(w, sql: "SELECT id FROM culture"))
            var ledger = EventLedger()
            let existing = try EventRecord
                .filter(Column("id") == event.id.rawValue)
                .fetchOne(w)
            guard existing == nil else {
                throw RiseLogError.duplicateEventID(event.id)
            }
            // Kind/payload agreement + duplicate rules come from append().
            try ledger.append(event)
            guard known.contains(event.cultureId.rawValue) else {
                throw RiseLogError.unknownCulture(event.cultureId)
            }
            if case .split(let parent, _) = event.payload {
                guard known.contains(parent.rawValue) else {
                    throw RiseLogError.unknownParent(parent)
                }
            }
            try EventRecord(event, loggedAt: loggedAt).insert(w)
        }
    }

    /// The ordered timeline for one culture: `occurredAt`, then `loggedAt`,
    /// then event id — deterministic at every level (see class docs).
    /// Uses the `event_culture_occurred` covering index.
    public func events(for cultureId: CultureID) throws -> [Event] {
        try reader.read { r in
            let rows = try EventRecord
                .filter(Column("cultureId") == cultureId.rawValue)
                .order(Column("occurredAt"), Column("loggedAt"), Column("id"))
                .fetchAll(r)
            return try rows.map { try $0.toDomain() }
        }
    }

    /// Every event across cultures in the same deterministic order.
    public func allEvents() throws -> [Event] {
        try reader.read { r in
            let rows = try EventRecord
                .order(Column("occurredAt"), Column("loggedAt"), Column("id"))
                .fetchAll(r)
            return try rows.map { try $0.toDomain() }
        }
    }

    public func event(withId id: EventID) throws -> Event? {
        try reader.read { r in
            try EventRecord.fetchOne(r, key: id.rawValue).map { try $0.toDomain() }
        }
    }

    // MARK: - Derived queries (indexed)

    /// The most recent feed for a culture, per the ledger ordering.
    /// `nil` means "no feed recorded" — never guessed.
    public func lastFeed(for cultureId: CultureID) throws -> Event? {
        try reader.read { r in
            guard let row = try EventRecord
                .filter(Column("cultureId") == cultureId.rawValue
                        && Column("kind") == Event.Kind.feed.rawValue)
                .order(Column("occurredAt").desc, Column("loggedAt").desc, Column("id").desc)
                .fetchOne(r)
            else { return nil }
            return try row.toDomain()
        }
    }

    /// Materialized lineage edges (parent, child, separatedAt) ordered for
    /// stable replay into `LineageGraph`.
    public func lineageEdges() throws -> [(parent: CultureID, child: CultureID, separatedAt: Date)] {
        try reader.read { r in
            try Row
                .fetchAll(r, sql: """
                    SELECT parentId, childId, separatedAt FROM lineage_edge
                    ORDER BY separatedAt, parentId, childId
                    """)
                .map { row in
                    (parent: CultureID(rawValue: row[0]),
                     child: CultureID(rawValue: row[1]),
                     separatedAt: row[2])
                }
        }
    }

    /// The full ledger + cultures snapshot as an in-memory `EventLedger`
    /// for the pure `StatusEngine` — the store feeds derivation, it never
    /// stores derived status.
    public func ledgerSnapshot() throws -> EventLedger {
        var ledger = EventLedger()
        for event in try allEvents() {
            // Store insert already validated; append() cannot fail here
            // (ids unique by PK). Guard anyway to surface corruption.
            try ledger.append(event)
        }
        return ledger
    }
}
