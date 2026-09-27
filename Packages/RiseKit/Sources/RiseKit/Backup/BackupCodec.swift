import Foundation

/// Errors that can occur during backup encoding, decoding, or restoration.
public enum BackupCodecError: Error, LocalizedError, Equatable, Sendable {
    case unsupportedSchemaVersion(found: Int, supported: Int)
    case corruptArchive(String)
    case emptyArchive
    case validationFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchemaVersion(found, supported):
            return "Unsupported backup schema version \(found) (current app version supports up to \(supported)). Please update Rise Log to restore this backup."
        case let .corruptArchive(details):
            return "Corrupt or invalid backup file: \(details)"
        case .emptyArchive:
            return "Backup archive contains no data."
        case let .validationFailed(reason):
            return "Backup validation failed: \(reason)"
        }
    }
}

/// A versioned backup archive representing the entire persistent state of Rise Log.
public struct BackupArchive: Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var appVersion: String
    public var exportedAt: Date
    public var cultures: [Culture]
    public var events: [(event: Event, loggedAt: Date)]

    public init(
        schemaVersion: Int = BackupArchive.currentSchemaVersion,
        appVersion: String = "0.1.0",
        exportedAt: Date = Date(),
        cultures: [Culture],
        events: [(event: Event, loggedAt: Date)]
    ) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.exportedAt = exportedAt
        self.cultures = cultures
        self.events = events
    }

    public static func == (lhs: BackupArchive, rhs: BackupArchive) -> Bool {
        guard lhs.schemaVersion == rhs.schemaVersion,
              lhs.appVersion == rhs.appVersion,
              abs(lhs.exportedAt.timeIntervalSince(rhs.exportedAt)) < 0.001,
              lhs.cultures == rhs.cultures,
              lhs.events.count == rhs.events.count else {
            return false
        }
        for (i, leftPair) in lhs.events.enumerated() {
            let rightPair = rhs.events[i]
            guard leftPair.event == rightPair.event,
                  abs(leftPair.loggedAt.timeIntervalSince(rightPair.loggedAt)) < 0.001 else {
                return false
            }
        }
        return true
    }
}

/// Summary of changes that will occur if a backup replaces the current store.
public struct BackupRestorePreview: Equatable, Sendable {
    public var incomingCultureCount: Int
    public var currentCultureCount: Int
    public var addedCultureNames: [String]
    public var removedCultureNames: [String]
    public var keptCultureNames: [String]

    public var incomingEventCount: Int
    public var currentEventCount: Int
    public var addedEventCount: Int
    public var removedEventCount: Int

    public init(
        incomingCultureCount: Int,
        currentCultureCount: Int,
        addedCultureNames: [String],
        removedCultureNames: [String],
        keptCultureNames: [String],
        incomingEventCount: Int,
        currentEventCount: Int,
        addedEventCount: Int,
        removedEventCount: Int
    ) {
        self.incomingCultureCount = incomingCultureCount
        self.currentCultureCount = currentCultureCount
        self.addedCultureNames = addedCultureNames
        self.removedCultureNames = removedCultureNames
        self.keptCultureNames = keptCultureNames
        self.incomingEventCount = incomingEventCount
        self.currentEventCount = currentEventCount
        self.addedEventCount = addedEventCount
        self.removedEventCount = removedEventCount
    }
}

// MARK: - Codable Transfer DTOs

struct BackupCultureDTO: Codable {
    var id: String
    var name: String
    var typePredefined: String?
    var typeCustom: String?
    var cadenceEveryHours: Int?
    var cadenceGraceHours: Int?
    var createdAt: String

    init(from culture: Culture, formatter: ISO8601DateFormatter) {
        self.id = culture.id.rawValue
        self.name = culture.name
        switch culture.type.kind {
        case .predefined(let p):
            self.typePredefined = p.rawValue
            self.typeCustom = nil
        case .custom(let name):
            self.typePredefined = nil
            self.typeCustom = name
        }
        self.cadenceEveryHours = culture.cadence?.everyHours
        self.cadenceGraceHours = culture.cadence?.graceHours
        self.createdAt = formatter.string(from: culture.createdAt)
    }

    func toDomain(formatter: ISO8601DateFormatter) throws -> Culture {
        guard let created = formatter.date(from: createdAt) else {
            throw BackupCodecError.corruptArchive("Invalid createdAt timestamp for culture '\(id)': \(createdAt)")
        }
        let type: CultureType
        if let predefinedRaw = typePredefined, let p = PredefinedCultureType(rawValue: predefinedRaw) {
            switch p {
            case .starter: type = .starter
            case .kombucha: type = .kombucha
            case .kimchi: type = .kimchi
            case .yogurt: type = .yogurt
            case .vinegar: type = .vinegar
            }
        } else if let custom = typeCustom {
            guard let c = CultureType(customName: custom) else {
                throw BackupCodecError.corruptArchive("Blank custom type name for culture '\(id)'")
            }
            type = c
        } else {
            throw BackupCodecError.corruptArchive("Culture '\(id)' missing type definition")
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
            createdAt: created
        )
    }
}

struct BackupEventDTO: Codable {
    var id: String
    var cultureId: String
    var kind: String
    var occurredAt: String
    var loggedAt: String
    var flourGrams: Double?
    var waterGrams: Double?
    var stage: String?
    var flourUsedGrams: Double?
    var removedGrams: Double?
    var noteText: String?
    var splitParentId: String?
    var separatedAt: String?

    init(from event: Event, loggedAt: Date, formatter: ISO8601DateFormatter) {
        self.id = event.id.rawValue
        self.cultureId = event.cultureId.rawValue
        self.kind = event.kind.rawValue
        self.occurredAt = formatter.string(from: event.occurredAt)
        self.loggedAt = formatter.string(from: loggedAt)

        switch event.payload {
        case .feed(let amount):
            self.flourGrams = amount.flourGrams
            self.waterGrams = amount.waterGrams
        case .riseCheck(let riseStage):
            self.stage = riseStage.rawValue
        case .bottle:
            break
        case .bake(let flourUsed):
            self.flourUsedGrams = flourUsed
        case .discard(let removed):
            self.removedGrams = removed
        case .note(let text):
            self.noteText = text
        case .split(let parent, let separated):
            self.splitParentId = parent.rawValue
            self.separatedAt = formatter.string(from: separated)
        }
    }

    func toDomain(formatter: ISO8601DateFormatter) throws -> (event: Event, loggedAt: Date) {
        guard let occurred = formatter.date(from: occurredAt) else {
            throw BackupCodecError.corruptArchive("Invalid occurredAt date for event '\(id)': \(occurredAt)")
        }
        guard let logged = formatter.date(from: loggedAt) else {
            throw BackupCodecError.corruptArchive("Invalid loggedAt date for event '\(id)': \(loggedAt)")
        }
        guard let eventKind = Event.Kind(rawValue: kind) else {
            throw BackupCodecError.corruptArchive("Unknown event kind '\(kind)' for event '\(id)'")
        }

        let payload: EventPayload
        switch eventKind {
        case .feed:
            payload = .feed(FeedAmount(flourGrams: flourGrams, waterGrams: waterGrams))
        case .riseCheck:
            guard let stageRaw = stage, let s = RiseStage(rawValue: stageRaw) else {
                throw BackupCodecError.corruptArchive("Invalid rise stage for event '\(id)'")
            }
            payload = .riseCheck(s)
        case .bottle:
            payload = .bottle
        case .bake:
            payload = .bake(flourUsedGrams: flourUsedGrams)
        case .discard:
            payload = .discard(removedGrams: removedGrams)
        case .note:
            guard let note = noteText else {
                throw BackupCodecError.corruptArchive("Missing note text for note event '\(id)'")
            }
            payload = .note(note)
        case .split:
            guard let parent = splitParentId, let sepStr = separatedAt, let sep = formatter.date(from: sepStr) else {
                throw BackupCodecError.corruptArchive("Missing split parent or separatedAt date for event '\(id)'")
            }
            payload = .split(parent: CultureID(rawValue: parent), separatedAt: sep)
        }

        let domainEvent = Event(
            id: EventID(rawValue: id),
            cultureId: CultureID(rawValue: cultureId),
            kind: eventKind,
            occurredAt: occurred,
            payload: payload
        )
        return (domainEvent, logged)
    }
}

struct BackupArchiveDTO: Codable {
    var schemaVersion: Int
    var appVersion: String
    var exportedAt: String
    var cultures: [BackupCultureDTO]
    var events: [BackupEventDTO]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case appVersion = "app_version"
        case exportedAt = "exported_at"
        case cultures
        case events
    }
}

// MARK: - Codec Engine

public enum BackupCodec {
    /// Builds an ISO8601 formatter with millisecond precision.
    ///
    /// Constructed per call (not a shared static) because `ISO8601DateFormatter`
    /// is not `Sendable` and Swift 6 strict concurrency rejects shared mutable
    /// formatters. Backup encode/decode is a rare, user-initiated operation,
    /// so the per-call allocation is negligible.
    private static func makeFormatter(fractionalSeconds: Bool) -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = fractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return f
    }

    private static func parseDate(_ string: String, formatter: ISO8601DateFormatter) -> Date? {
        formatter.date(from: string) ?? makeFormatter(fractionalSeconds: false).date(from: string)
    }

    /// Encodes a BackupArchive into a pretty-printed JSON data payload.
    public static func encodeJSON(_ archive: BackupArchive) throws -> Data {
        let formatter = makeFormatter(fractionalSeconds: true)
        let dto = BackupArchiveDTO(
            schemaVersion: archive.schemaVersion,
            appVersion: archive.appVersion,
            exportedAt: formatter.string(from: archive.exportedAt),
            cultures: archive.cultures.map { BackupCultureDTO(from: $0, formatter: formatter) },
            events: archive.events.map { BackupEventDTO(from: $0.event, loggedAt: $0.loggedAt, formatter: formatter) }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(dto)
    }

    /// Decodes and validates a JSON backup payload.
    public static func decodeJSON(_ data: Data) throws -> BackupArchive {
        let dto: BackupArchiveDTO
        do {
            let decoder = JSONDecoder()
            dto = try decoder.decode(BackupArchiveDTO.self, from: data)
        } catch {
            throw BackupCodecError.corruptArchive("Failed to parse archive JSON: \(error.localizedDescription)")
        }

        guard dto.schemaVersion == BackupArchive.currentSchemaVersion else {
            throw BackupCodecError.unsupportedSchemaVersion(
                found: dto.schemaVersion,
                supported: BackupArchive.currentSchemaVersion
            )
        }

        let formatter = makeFormatter(fractionalSeconds: true)

        guard let exportedAt = parseDate(dto.exportedAt, formatter: formatter) else {
            throw BackupCodecError.corruptArchive("Invalid exportedAt timestamp: \(dto.exportedAt)")
        }

        var cultures: [Culture] = []
        var cultureIds = Set<String>()
        for cDto in dto.cultures {
            if cultureIds.contains(cDto.id) {
                throw BackupCodecError.corruptArchive("Duplicate culture ID in archive: '\(cDto.id)'")
            }
            cultureIds.insert(cDto.id)
            let culture = try cDto.toDomain(formatter: formatter)
            cultures.append(culture)
        }

        var events: [(event: Event, loggedAt: Date)] = []
        var eventIds = Set<String>()
        for eDto in dto.events {
            if eventIds.contains(eDto.id) {
                throw BackupCodecError.corruptArchive("Duplicate event ID in archive: '\(eDto.id)'")
            }
            eventIds.insert(eDto.id)
            guard cultureIds.contains(eDto.cultureId) else {
                throw BackupCodecError.corruptArchive("Event '\(eDto.id)' references unknown culture '\(eDto.cultureId)'")
            }
            if let splitParent = eDto.splitParentId {
                guard cultureIds.contains(splitParent) else {
                    throw BackupCodecError.corruptArchive("Split event '\(eDto.id)' references unknown parent culture '\(splitParent)'")
                }
            }
            let pair = try eDto.toDomain(formatter: formatter)
            events.append(pair)
        }

        return BackupArchive(
            schemaVersion: dto.schemaVersion,
            appVersion: dto.appVersion,
            exportedAt: exportedAt,
            cultures: cultures,
            events: events
        )
    }

    /// Computes a preview diff between an incoming archive and the current store state.
    public static func previewReplace(
        archive: BackupArchive,
        currentCultures: [Culture],
        currentEvents: [Event]
    ) -> BackupRestorePreview {
        let currentCultureMap = Dictionary(uniqueKeysWithValues: currentCultures.map { ($0.id, $0) })
        let incomingCultureMap = Dictionary(uniqueKeysWithValues: archive.cultures.map { ($0.id, $0) })

        var addedCultureNames: [String] = []
        var keptCultureNames: [String] = []
        for culture in archive.cultures {
            if currentCultureMap[culture.id] != nil {
                keptCultureNames.append(culture.name)
            } else {
                addedCultureNames.append(culture.name)
            }
        }

        var removedCultureNames: [String] = []
        for culture in currentCultures {
            if incomingCultureMap[culture.id] == nil {
                removedCultureNames.append(culture.name)
            }
        }

        let currentEventIds = Set(currentEvents.map(\.id))
        let incomingEventIds = Set(archive.events.map(\.event.id))

        let addedEvents = incomingEventIds.subtracting(currentEventIds).count
        let removedEvents = currentEventIds.subtracting(incomingEventIds).count

        return BackupRestorePreview(
            incomingCultureCount: archive.cultures.count,
            currentCultureCount: currentCultures.count,
            addedCultureNames: addedCultureNames.sorted(),
            removedCultureNames: removedCultureNames.sorted(),
            keptCultureNames: keptCultureNames.sorted(),
            incomingEventCount: archive.events.count,
            currentEventCount: currentEvents.count,
            addedEventCount: addedEvents,
            removedEventCount: removedEvents
        )
    }

    /// Exports the full event ledger and associated cultures to an RFC 4180-compliant CSV string.
    public static func exportCSV(
        cultures: [Culture],
        events: [(event: Event, loggedAt: Date)]
    ) -> String {
        let formatter = makeFormatter(fractionalSeconds: true)
        let cultureMap = Dictionary(uniqueKeysWithValues: cultures.map { ($0.id, $0.name) })
        let sortedEvents = events.sorted {
            if $0.event.occurredAt != $1.event.occurredAt {
                return $0.event.occurredAt < $1.event.occurredAt
            }
            if $0.loggedAt != $1.loggedAt {
                return $0.loggedAt < $1.loggedAt
            }
            return $0.event.id.rawValue < $1.event.id.rawValue
        }

        var output = "event_id,occurred_at,logged_at,culture_id,culture_name,kind,summary,flour_grams,water_grams,stage,flour_used_grams,removed_grams,note_text,split_parent_id,separated_at\r\n"

        for pair in sortedEvents {
            let event = pair.event
            let cultureName = cultureMap[event.cultureId] ?? ""
            let occurredStr = formatter.string(from: event.occurredAt)
            let loggedStr = formatter.string(from: pair.loggedAt)

            var flourStr = ""
            var waterStr = ""
            var stageStr = ""
            var flourUsedStr = ""
            var removedStr = ""
            var noteStr = ""
            var parentStr = ""
            var sepStr = ""

            switch event.payload {
            case .feed(let amount):
                if let f = amount.flourGrams { flourStr = String(f) }
                if let w = amount.waterGrams { waterStr = String(w) }
            case .riseCheck(let stage):
                stageStr = stage.rawValue
            case .bottle:
                break
            case .bake(let flour):
                if let f = flour { flourUsedStr = String(f) }
            case .discard(let rem):
                if let r = rem { removedStr = String(r) }
            case .note(let text):
                noteStr = text
            case .split(let parent, let separatedAt):
                parentStr = parent.rawValue
                sepStr = formatter.string(from: separatedAt)
            }

            let fields = [
                event.id.rawValue,
                occurredStr,
                loggedStr,
                event.cultureId.rawValue,
                cultureName,
                event.kind.rawValue,
                event.displaySummary,
                flourStr,
                waterStr,
                stageStr,
                flourUsedStr,
                removedStr,
                noteStr,
                parentStr,
                sepStr
            ]

            let escapedRow = fields.map { escapeCSVField($0) }.joined(separator: ",")
            output += escapedRow + "\r\n"
        }

        return output
    }

    /// Escapes a CSV field according to RFC 4180 with spreadsheet formula injection protection.
    private static func escapeCSVField(_ value: String) -> String {
        var str = value
        // Defense against CSV formula injection (OWASP):
        // If first character is =, +, -, @, prefix with a single quote.
        if let first = str.first, first == "=" || first == "+" || first == "-" || first == "@" {
            str = "'" + str
        }

        let needsQuotes = str.contains(",") || str.contains("\"") || str.contains("\n") || str.contains("\r")
        if needsQuotes {
            let escaped = str.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return str
    }
}
