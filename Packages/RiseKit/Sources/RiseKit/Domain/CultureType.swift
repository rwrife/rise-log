import Foundation

/// Predefined culture taxonomy. Users may also define their own types
/// (see `CultureType.Kind.custom`).
public enum PredefinedCultureType: String, CaseIterable, Sendable {
    case starter
    case kombucha
    case kimchi
    case yogurt
    case vinegar

    public var displayName: String {
        switch self {
        case .starter: "Sourdough starter"
        case .kombucha: "Kombucha"
        case .kimchi: "Kimchi"
        case .yogurt: "Yogurt"
        case .vinegar: "Vinegar mother"
        }
    }
}

/// A culture's type: one of the predefined kinds or a user-defined label.
/// User-defined names are non-empty (trimmed); `init(customName:)` rejects
/// blank input rather than normalizing it into a meaningless label.
public struct CultureType: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case predefined(PredefinedCultureType)
        case custom(name: String)
    }

    public let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let starter = CultureType(kind: .predefined(.starter))
    public static let kombucha = CultureType(kind: .predefined(.kombucha))
    public static let kimchi = CultureType(kind: .predefined(.kimchi))
    public static let yogurt = CultureType(kind: .predefined(.yogurt))
    public static let vinegar = CultureType(kind: .predefined(.vinegar))

    /// Creates a user-defined type. Returns `nil` for blank/whitespace names.
    public init?(customName: String) {
        let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.kind = .custom(name: trimmed)
    }

    public var isPredefined: Bool {
        if case .predefined = kind { true } else { false }
    }

    public var displayName: String {
        switch kind {
        case .predefined(let p): p.displayName
        case .custom(let name): name
        }
    }
}
