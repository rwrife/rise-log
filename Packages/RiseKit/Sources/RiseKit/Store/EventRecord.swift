import Foundation
import GRDB

/// GRDB record for the append-only `event` table (issue #3, migration v1).
///
/// Payload encoding: each event kind stores only the columns its payload
/// needs (`EventPayload` ⇄ columns is bijective for valid rows, so kind and
/// payload can always be re-derived). One exception: `.note("")` and
/// `.note(nil)` would collapse to the same row, so `EventLedger`'s
/// kind/payload validation is applied BEFORE insertion
/// (`RiseLogError.payloadKindMismatch`) and `noteText` is allowed to be
/// NULL only for non-note kinds.
///
/// Timestamps: `occurredAt` is the primary ordering column (second
/// precision — see `RiseLogStore` note). `loggedAt` keeps full millisecond
/// precision as the immutable audit timestamp proving append order even
/// when `occurredAt` values collide or are back-dated.
struct EventRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    static let databaseTableName = "event"

    var id: String
    var cultureId: String
    var kind: String
    var occurredAt: Date
    var loggedAt: Date
    var flourGrams: Double?
    var waterGrams: Double?
    var stage: String?
    var flourUsedGrams: Double?
    var removedGrams: Double?
    var noteText: String?
    var splitParentId: String?
    var separatedAt: Date?

    /// `loggedAt` is server(now)-defaulted in real use; tests and replay
    /// pass it explicitly for determinism.
    init(_ event: Event, loggedAt: Date) {
        self.id = event.id.rawValue
        self.cultureId = event.cultureId.rawValue
        self.kind = event.kind.rawValue
        self.occurredAt = event.occurredAt
        self.loggedAt = loggedAt
        switch event.payload {
        case .feed(let amount):
            self.flourGrams = amount.flourGrams
            self.waterGrams = amount.waterGrams
            self.stage = nil
            self.flourUsedGrams = nil
            self.removedGrams = nil
            self.noteText = nil
            self.splitParentId = nil
            self.separatedAt = nil
        case .riseCheck(let riseStage):
            self.flourGrams = nil
            self.waterGrams = nil
            self.stage = riseStage.rawValue
            self.flourUsedGrams = nil
            self.removedGrams = nil
            self.noteText = nil
            self.splitParentId = nil
            self.separatedAt = nil
        case .bottle:
            self.flourGrams = nil
            self.waterGrams = nil
            self.stage = nil
            self.flourUsedGrams = nil
            self.removedGrams = nil
            self.noteText = nil
            self.splitParentId = nil
            self.separatedAt = nil
        case .bake(let flourUsedGrams):
            self.flourGrams = nil
            self.waterGrams = nil
            self.stage = nil
            self.flourUsedGrams = flourUsedGrams
            self.removedGrams = nil
            self.noteText = nil
            self.splitParentId = nil
            self.separatedAt = nil
        case .discard(let removedGrams):
            self.flourGrams = nil
            self.waterGrams = nil
            self.stage = nil
            self.flourUsedGrams = nil
            self.removedGrams = removedGrams
            self.noteText = nil
            self.splitParentId = nil
            self.separatedAt = nil
        case .note(let text):
            self.flourGrams = nil
            self.waterGrams = nil
            self.stage = nil
            self.flourUsedGrams = nil
            self.removedGrams = nil
            self.noteText = text
            self.splitParentId = nil
            self.separatedAt = nil
        case .split(let parent, let separatedAt):
            self.flourGrams = nil
            self.waterGrams = nil
            self.stage = nil
            self.flourUsedGrams = nil
            self.removedGrams = nil
            self.noteText = nil
            self.splitParentId = parent.rawValue
            self.separatedAt = separatedAt
        }
    }

    /// Rebuilds the domain event (`occurredAt`-ordered reading is done by
    /// queries; the domain `Event` carries no `loggedAt`).
    ///
    /// Throws `payloadKindMismatch` for rows whose kind is unrecognized or
    /// whose payload columns contradict the kind — corruption and
    /// future-version rows surface as errors, never as silently wrong
    /// domain values.
    func toDomain() throws -> Event {
        guard let eventKind = Event.Kind(rawValue: kind) else {
            throw RiseLogError.payloadKindMismatch(eventId: EventID(rawValue: id))
        }
        let payload: EventPayload
        switch eventKind {
        case .feed:
            guard stage == nil, flourUsedGrams == nil, removedGrams == nil,
                  noteText == nil, splitParentId == nil, separatedAt == nil
            else { throw RiseLogError.payloadKindMismatch(eventId: EventID(rawValue: id)) }
            payload = .feed(FeedAmount(flourGrams: flourGrams, waterGrams: waterGrams))
        case .riseCheck:
            guard let raw = stage, let riseStage = RiseStage(rawValue: raw),
                  flourGrams == nil, waterGrams == nil, flourUsedGrams == nil,
                  removedGrams == nil, noteText == nil, splitParentId == nil,
                  separatedAt == nil
            else { throw RiseLogError.payloadKindMismatch(eventId: EventID(rawValue: id)) }
            payload = .riseCheck(riseStage)
        case .bottle:
            guard flourGrams == nil, waterGrams == nil, stage == nil,
                  flourUsedGrams == nil, removedGrams == nil, noteText == nil,
                  splitParentId == nil, separatedAt == nil
            else { throw RiseLogError.payloadKindMismatch(eventId: EventID(rawValue: id)) }
            payload = .bottle
        case .bake:
            guard flourGrams == nil, waterGrams == nil, stage == nil,
                  removedGrams == nil, noteText == nil, splitParentId == nil,
                  separatedAt == nil
            else { throw RiseLogError.payloadKindMismatch(eventId: EventID(rawValue: id)) }
            payload = .bake(flourUsedGrams: flourUsedGrams)
        case .discard:
            guard flourGrams == nil, waterGrams == nil, stage == nil,
                  flourUsedGrams == nil, noteText == nil, splitParentId == nil,
                  separatedAt == nil
            else { throw RiseLogError.payloadKindMismatch(eventId: EventID(rawValue: id)) }
            payload = .discard(removedGrams: removedGrams)
        case .note:
            guard flourGrams == nil, waterGrams == nil, stage == nil,
                  flourUsedGrams == nil, removedGrams == nil,
                  splitParentId == nil, separatedAt == nil
            else { throw RiseLogError.payloadKindMismatch(eventId: EventID(rawValue: id)) }
            // kind == .note ⇒ payload column must be present (blank string
            // allowed); NULL would be an ambiguous/corrupt row.
            guard let text = noteText else {
                throw RiseLogError.payloadKindMismatch(eventId: EventID(rawValue: id))
            }
            payload = .note(text)
        case .split:
            guard flourGrams == nil, waterGrams == nil, stage == nil,
                  flourUsedGrams == nil, removedGrams == nil, noteText == nil,
                  let parent = splitParentId, let separated = separatedAt
            else { throw RiseLogError.payloadKindMismatch(eventId: EventID(rawValue: id)) }
            payload = .split(parent: CultureID(rawValue: parent), separatedAt: separated)
        }
        return Event(
            id: EventID(rawValue: id),
            cultureId: CultureID(rawValue: cultureId),
            kind: eventKind,
            occurredAt: occurredAt,
            payload: payload
        )
    }
}
