import Foundation

/// Errors surfaced by ledger and lineage operations.
public enum RiseLogError: Error, Hashable, Sendable {
    /// Appending an event whose id is already present in the ledger.
    case duplicateEventID(EventID)
    /// An event's kind and payload disagree (e.g. `.feed` kind, note payload).
    case payloadKindMismatch(eventId: EventID)
    /// An event references a culture that the store does not know.
    case unknownCulture(CultureID)
    /// Adding a split edge would create a cycle in the lineage graph.
    case lineageCycle(parent: CultureID, child: CultureID)
    /// A split edge points at a parent culture that is unknown.
    case unknownParent(CultureID)
}

/// Append-only ledger of events for a set of cultures.
///
/// Invariants (tested):
/// - `append` is the only mutation; stored events are never modified or removed.
/// - Event ids are unique across the whole ledger.
/// - `events(for:)` is returned in occurredAt order with a stable tiebreak.
public struct EventLedger: Sendable {
    private var storage: [EventID: Event] = [:]

    public init() {}

    public var count: Int { storage.count }

    /// Appends an event. Fails on duplicate id (ledger is append-once per id)
    /// or on kind/payload disagreement.
    public mutating func append(_ event: Event) throws {
        guard storage[event.id] == nil else {
            throw RiseLogError.duplicateEventID(event.id)
        }
        let payloadMatchesKind: Bool
        switch (event.kind, event.payload) {
        case (.feed, .feed), (.riseCheck, .riseCheck), (.bottle, .bottle),
             (.bake, .bake), (.discard, .discard), (.note, .note), (.split, .split):
            payloadMatchesKind = true
        default:
            payloadMatchesKind = false
        }
        guard payloadMatchesKind else {
            throw RiseLogError.payloadKindMismatch(eventId: event.id)
        }
        storage[event.id] = event
    }

    /// All events for a culture, ordered by `occurredAt`, ties broken by
    /// insertion-stable event id so ordering is deterministic.
    public func events(for cultureId: CultureID) -> [Event] {
        storage.values
            .filter { $0.cultureId == cultureId }
            .sorted {
                if $0.occurredAt != $1.occurredAt {
                    return $0.occurredAt < $1.occurredAt
                }
                return $0.id.rawValue < $1.id.rawValue
            }
    }

    public func event(withId id: EventID) -> Event? {
        storage[id]
    }

    public func containsEvent(withId id: EventID) -> Bool {
        storage[id] != nil
    }

    /// Snapshot of every event (unordered) for export/backup.
    public var allEvents: [Event] {
        storage.values.sorted { $0.id.rawValue < $1.id.rawValue }
    }
}
