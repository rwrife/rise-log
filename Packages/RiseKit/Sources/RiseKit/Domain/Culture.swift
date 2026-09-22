import Foundation

/// Stable identifier for a culture. String-backed so the store layer
/// (issue #3) can persist it without UUID serialization quirks.
public struct CultureID: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

/// A named living culture (one jar). Its status is never stored —
/// always re-derived from the ledger (`StatusEngine`).
public struct Culture: Hashable, Sendable {
    public let id: CultureID
    public var name: String
    public var type: CultureType
    /// Optional user-declared feeding cadence driving the due window.
    public var cadence: FeedingCadence?
    /// When the culture record was created in the app.
    public var createdAt: Date

    public init(
        id: CultureID,
        name: String,
        type: CultureType,
        cadence: FeedingCadence? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.cadence = cadence
        self.createdAt = createdAt
    }
}

/// User-declared feeding rhythm: "feed roughly every N hours, ±G grace".
/// Pure declaration — the user owns the number; the engine never invents one.
public struct FeedingCadence: Hashable, Sendable {
    public let everyHours: Int
    public let graceHours: Int

    /// Failable: cadence values must be positive (and grace non-negative).
    public init?(everyHours: Int, graceHours: Int = 0) {
        guard everyHours > 0, graceHours >= 0 else { return nil }
        self.everyHours = everyHours
        self.graceHours = graceHours
    }
}
