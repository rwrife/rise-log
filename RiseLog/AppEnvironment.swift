import Foundation
import Observation
import RiseKit

/// App-wide observable state (issue #4): the durable store plus the
/// in-memory projection the views render (cultures + ledger snapshot).
///
/// Single source of truth on screen: every badge/timeline line is a pure
/// function of (store contents, clock) via `StatusEngine` — the view never
/// caches a derived value. Mutations go through the store first, then
/// `reload()`, so the UI is a mirror of persisted truth (a crash can never
/// leave the screen showing something the ledger doesn't contain).
///
/// Store calls are synchronous GRDB calls on the main actor. At jar-wall
/// scale (tens of cultures, thousands of events) this is sub-millisecond;
/// if that ever changes, move reads off-main behind observation, not
/// in front of a cache.
@MainActor
@Observable
final class AppEnvironment {
    let store: RiseLogStore

    private(set) var cultures: [Culture] = []
    private(set) var ledger = EventLedger()

    private let calendar = Calendar.current
    private let engine: StatusEngine

    /// The calendar + clock used for all on-screen derivation. Tests and
    /// later snapshot tooling can pin this; production uses `Date()`.
    var now: Date { Date() }

    /// Boot the app environment: open the store, recovering once from an
    /// unreadable database by resetting it (documented, lossy — backup/
    /// restore in issue #6 provides the recovery path).
    ///
    /// UI-test hook: launch argument `-uitest-reset-store` deletes the
    /// on-disk store at boot so each XCUITest journey starts from the true
    /// empty state (same idiom as the seat-weave/split-slip fleet).
    static func bootstrap() -> AppEnvironment {
        let resetRequested =
            CommandLine.arguments.contains("-uitest-reset-store")
            || ProcessInfo.processInfo.environment["RISELOG_TEST_RESET_STORE"] == "1"
        do {
            if resetRequested { try deleteStoreFile() }
            return try AppEnvironment()
        } catch {
            // Last-resort recovery: one reset + reopen. A second failure
            // means the sandbox itself is unusable — crashing with the
            // underlying error is more honest than rendering a blank app.
            try? deleteStoreFile()
            do { return try AppEnvironment() } catch {
                fatalError("Rise Log store unusable: \(error)")
            }
        }
    }

    private static func storeURL() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("RiseLog", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("riselog.sqlite")
    }

    private static func deleteStoreFile() throws {
        let url = try storeURL()
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    init() throws {
        store = try RiseLogStore(url: try Self.storeURL())
        engine = StatusEngine(calendar: Calendar.current)
        reload()
    }

    // MARK: - Projection

    /// Re-read cultures + ledger from the store. Called after every write.
    func reload() {
        do {
            cultures = try store.allCultures()
            ledger = try store.ledgerSnapshot()
        } catch {
            // A read failure after a successful write must never present
            // stale data as current: surface an empty projection loudly.
            cultures = []
            ledger = EventLedger()
        }
    }

    func culture(_ id: CultureID) -> Culture? {
        cultures.first { $0.id == id }
    }

    /// Derived status at `now` — pure call into RiseKit.
    func status(for id: CultureID) -> CultureStatus {
        guard let culture = culture(id) else {
            return CultureStatus(hoursSinceLastFeed: .unknown, risePhase: .unknown,
                                 fermentDays: .unknown, dueWindow: .unknown)
        }
        return engine.status(for: culture, ledger: ledger, now: now)
    }

    /// Newest-first timeline for one culture (the store returns oldest-first).
    func timeline(for id: CultureID) -> [Event] {
        (try? store.events(for: id))?.reversed() ?? []
    }

    // MARK: - Mutations (store-first, then reload)

    /// Create a culture with a trimmed non-empty name. Returns nil (and
    /// writes nothing) for blank names — validation mirrors the UI rule.
    @discardableResult
    func createCulture(name: String, type: CultureType = .starter) throws -> Culture? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let culture = Culture(id: CultureID(rawValue: UUID().uuidString),
                              name: trimmed, type: type, createdAt: now)
        try store.saveCulture(culture)
        reload()
        return culture
    }

    /// Seed the built-in sample culture (onboarding + wall action).
    func addSample() throws {
        try SampleData.seed(into: store, anchor: now, calendar: calendar)
        reload()
    }

    // MARK: Logging helpers — one per event kind; every one is append-only.

    func logFeed(_ id: CultureID, flour: Double?, water: Double?,
                 occurredAt: Date? = nil) throws -> Event {
        try log(.feed, id, occurredAt, .feed(FeedAmount(flourGrams: flour, waterGrams: water)))
    }

    func logCheck(_ id: CultureID, stage: RiseStage) throws -> Event {
        try log(.riseCheck, id, nil, .riseCheck(stage))
    }

    func logBottle(_ id: CultureID) throws -> Event {
        try log(.bottle, id, nil, .bottle)
    }

    func logBake(_ id: CultureID, flourUsed: Double?) throws -> Event {
        try log(.bake, id, nil, .bake(flourUsedGrams: flourUsed))
    }

    func logDiscard(_ id: CultureID, removed: Double?) throws -> Event {
        try log(.discard, id, nil, .discard(removedGrams: removed))
    }

    func logNote(_ id: CultureID, text: String) throws -> Event? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return try log(.note, id, nil, .note(trimmed))
    }

    @discardableResult
    private func log(_ kind: Event.Kind, _ cultureId: CultureID,
                     _ occurredAt: Date?, _ payload: EventPayload) throws -> Event {
        let event = Event(id: EventID(rawValue: UUID().uuidString),
                          cultureId: cultureId, kind: kind,
                          occurredAt: occurredAt ?? now, payload: payload)
        try store.insertEvent(event, loggedAt: now)
        reload()
        return event
    }

    // MARK: Undo / correction (append-only — never an edit)

    /// Undo a just-logged feed by appending the opposite action: a discard
    /// of the same amount. The ledger never retracts — the correction is a
    /// new, honest row ("correction event, not edit").
    func undoFeed(_ event: Event) throws {
        guard case .feed(let amount) = event.payload else { return }
        _ = try log(.discard, event.cultureId, nil,
                    .discard(removedGrams: amount.flourGrams))
    }

    /// Correct the newest event by re-appending it as a new event with the
    /// same payload at the current time (a later event supersedes it for
    /// every derivation). The original row stays in the ledger.
    func correctLatest(in cultureId: CultureID) throws {
        guard let latest = timeline(for: cultureId).first else { return }
        let occurredAt = max(now, latest.occurredAt.addingTimeInterval(1))
        let event = Event(id: EventID(rawValue: UUID().uuidString),
                          cultureId: cultureId, kind: latest.kind,
                          occurredAt: occurredAt, payload: latest.payload)
        try store.insertEvent(event, loggedAt: now)
        reload()
    }
}
