import Foundation

/// Stable identifier for an event.
public struct EventID: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

/// Visual stage the user records at a rise check. This is *the user's own
/// observation label* — the app never measures or infers it, and it carries
/// no food-safety meaning.
public enum RiseStage: String, CaseIterable, Sendable {
    case flat
    case rising
    case peaked
    case falling
}

/// Amount payload for a feed event (grams). Both nil-able because a user
/// may log "I fed it" without quantities.
public struct FeedAmount: Hashable, Sendable {
    public let flourGrams: Double?
    public let waterGrams: Double?

    public init(flourGrams: Double? = nil, waterGrams: Double? = nil) {
        self.flourGrams = flourGrams
        self.waterGrams = waterGrams
    }

    public static let unspecified = FeedAmount()
}

/// Payload attached to each event kind.
public enum EventPayload: Hashable, Sendable {
    case feed(FeedAmount)
    case riseCheck(RiseStage)
    case bottle
    case bake(flourUsedGrams: Double?)
    case discard(removedGrams: Double?)
    case note(String)
    /// Split: this culture was divided off `parent`, with the share
    /// separated at `separatedAt`.
    case split(parent: CultureID, separatedAt: Date)
}

/// One entry in a culture's append-only ledger. Events are never mutated
/// after the ledger accepts them; corrections are new events.
public struct Event: Hashable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case feed
        case riseCheck
        case bottle
        case bake
        case discard
        case note
        case split
    }

    public let id: EventID
    public let cultureId: CultureID
    public let kind: Kind
    /// When the thing actually happened (user-writable back-dating allowed).
    public let occurredAt: Date
    public let payload: EventPayload

    public init(
        id: EventID,
        cultureId: CultureID,
        kind: Kind,
        occurredAt: Date,
        payload: EventPayload
    ) {
        self.id = id
        self.cultureId = cultureId
        self.kind = kind
        self.occurredAt = occurredAt
        self.payload = payload
    }
}

extension Event {
    /// One-line plain-text rendering of the event for timelines and
    /// correction prompts. Pure (no `Date()` reads, no formatter singletons)
    /// so Linux CI can pin the exact strings the UI shows.
    /// Never contains safety/edibility vocabulary.
    public var displaySummary: String {
        switch payload {
        case .feed(let amount):
            if let flour = amount.flourGrams, let water = amount.waterGrams {
                return "Feed — \(Self.grams(flour)) flour + \(Self.grams(water)) water"
            }
            if let flour = amount.flourGrams {
                return "Feed — \(Self.grams(flour)) flour"
            }
            if let water = amount.waterGrams {
                return "Feed — \(Self.grams(water)) water"
            }
            return "Feed — amounts not recorded"
        case .riseCheck(let stage):
            return "Rise check — \(stage.displayName)"
        case .bottle:
            return "Bottle"
        case .bake(let flourUsedGrams):
            if let grams = flourUsedGrams {
                return "Bake — \(Self.grams(grams)) flour used"
            }
            return "Bake — flour used not recorded"
        case .discard(let removedGrams):
            if let grams = removedGrams {
                return "Discard — \(Self.grams(grams)) removed"
            }
            return "Discard — amount not recorded"
        case .note(let text):
            return "Note — \(text)"
        case .split(let parent, _):
            return "Split from \(parent.rawValue)"
        }
    }

    /// Whole grams render as integers; fractional grams keep one decimal.
    private static func grams(_ value: Double) -> String {
        if value == value.rounded() {
            return "\(Int(value)) g"
        }
        return String(format: "%.1f g", value)
    }
}
