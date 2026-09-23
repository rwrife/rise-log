import Foundation
import GRDB

/// GRDB record for the `culture` table (issue #3, migration v1).
///
/// Row shape mirrors the RiseKit domain `Culture`, flattened to
/// relational columns (no opaque blobs) so derived SQL queries and
/// later backup/export can read them directly.
///
/// Type encoding:
/// - predefined kinds → the `PredefinedCultureType` raw value ("starter", …)
///   with `customName` NULL.
/// - custom kinds → NULL `predefined` and the user label in `customName`.
struct CultureRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    static let databaseTableName = "culture"

    var id: String
    var name: String
    var predefined: String?
    var customName: String?
    var cadenceEveryHours: Int?
    var cadenceGraceHours: Int?
    var createdAt: Date

    init(_ culture: Culture) {
        self.id = culture.id.rawValue
        self.name = culture.name
        switch culture.type.kind {
        case .predefined(let p):
            self.predefined = p.rawValue
            self.customName = nil
        case .custom(let label):
            self.predefined = nil
            self.customName = label
        }
        self.cadenceEveryHours = culture.cadence?.everyHours
        self.cadenceGraceHours = culture.cadence?.graceHours
        self.createdAt = culture.createdAt
    }

    /// Rebuilds the domain value. Unknown type encodings (e.g. a row
    /// written by a future app version with a new predefined raw value)
    /// degrade to a custom type carrying the raw label — data is never
    /// dropped, matching the unknown-safe doctrine.
    func toDomain() -> Culture {
        let type: CultureType
        if let raw = predefined, let p = PredefinedCultureType(rawValue: raw) {
            switch p {
            case .starter: type = .starter
            case .kombucha: type = .kombucha
            case .kimchi: type = .kimchi
            case .yogurt: type = .yogurt
            case .vinegar: type = .vinegar
            }
        } else {
            // Custom row, or an unrecognized predefined code from a newer
            // app version: surface the stored label honestly as custom.
            let label = customName ?? predefined ?? "unknown"
            // `CultureType(customName:)` rejects only blank names; the
            // literal fallback is provably non-blank.
            type = CultureType(customName: label) ?? CultureType(customName: "unknown")!
        }
        let cadence: FeedingCadence?
        if let every = cadenceEveryHours {
            cadence = FeedingCadence(everyHours: every, graceHours: cadenceGraceHours ?? 0)
        } else {
            cadence = nil
        }
        return Culture(
            id: CultureID(rawValue: id),
            name: name,
            type: type,
            cadence: cadence,
            createdAt: createdAt
        )
    }
}
