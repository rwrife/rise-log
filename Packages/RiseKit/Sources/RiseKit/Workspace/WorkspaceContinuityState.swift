import Foundation

/// Persisted continuity contract for the workspace seam.
///
/// This type is UI-agnostic and Codable so the app layer can store it in
/// SceneStorage/UserDefaults and Linux tests can verify round-trip behavior
/// without SwiftUI.
public struct WorkspaceContinuityState: Codable, Equatable, Sendable {
    /// Currently selected culture id raw value (if any).
    public var selectedCultureID: String?

    /// Per-culture timeline anchor id.
    /// Key: culture id raw value. Value: event id raw value.
    public var timelineAnchorByCultureID: [String: String]

    public init(
        selectedCultureID: String? = nil,
        timelineAnchorByCultureID: [String: String] = [:]
    ) {
        self.selectedCultureID = selectedCultureID
        self.timelineAnchorByCultureID = timelineAnchorByCultureID
    }

    public mutating func setSelectedCultureID(_ id: String?) {
        selectedCultureID = id
    }

    public mutating func setTimelineAnchor(_ eventID: String, for cultureID: String) {
        timelineAnchorByCultureID[cultureID] = eventID
    }

    public mutating func clearTimelineAnchor(for cultureID: String) {
        timelineAnchorByCultureID.removeValue(forKey: cultureID)
    }

    public func timelineAnchor(for cultureID: String) -> String? {
        timelineAnchorByCultureID[cultureID]
    }

    public mutating func prune(keepingCultureIDs ids: Set<String>) {
        timelineAnchorByCultureID = timelineAnchorByCultureID.filter { ids.contains($0.key) }
        if let selectedCultureID, !ids.contains(selectedCultureID) {
            self.selectedCultureID = nil
        }
    }

    public var isEmpty: Bool {
        selectedCultureID == nil && timelineAnchorByCultureID.isEmpty
    }
}

public extension WorkspaceContinuityState {
    static let empty = Self()

    static let defaultMaxAnchors = 64

    func normalizedForStorage(maxAnchors: Int = defaultMaxAnchors) -> Self {
        guard timelineAnchorByCultureID.count > maxAnchors else { return self }
        var copy = self
        let overflow = timelineAnchorByCultureID.count - maxAnchors
        let keysToDrop = timelineAnchorByCultureID.keys.sorted().prefix(overflow)
        for key in keysToDrop {
            copy.timelineAnchorByCultureID.removeValue(forKey: key)
        }
        return copy
    }
}

public extension WorkspaceContinuityState {
    func toJSONString() throws -> String {
        let data = try JSONEncoder().encode(self)
        guard let string = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                data,
                .init(codingPath: [], debugDescription: "Workspace continuity JSON was not UTF-8")
            )
        }
        return string
    }

    static func fromJSONString(_ string: String) throws -> Self {
        try JSONDecoder().decode(Self.self, from: Data(string.utf8))
    }

    static func fromStorageOrEmpty(_ persisted: String?) -> Self {
        guard let persisted, !persisted.isEmpty else { return .empty }
        return (try? fromJSONString(persisted)) ?? .empty
    }

    var sceneStorageValueOrNilIfEmpty: String? {
        let normalized = normalizedForStorage()
        guard !normalized.isEmpty else { return nil }
        return try? normalized.toJSONString()
    }
}

public extension WorkspaceContinuityState {
    struct Envelope: Codable, Equatable, Sendable {
        public var version: Int
        public var payload: WorkspaceContinuityState

        public init(version: Int, payload: WorkspaceContinuityState) {
            self.version = version
            self.payload = payload
        }
    }

    static let storageVersion = 1

    func toVersionedJSONString() throws -> String {
        let data = try JSONEncoder().encode(Envelope(version: Self.storageVersion, payload: self))
        guard let string = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                data,
                .init(codingPath: [], debugDescription: "Workspace continuity envelope JSON was not UTF-8")
            )
        }
        return string
    }

    static func fromAnyJSONString(_ string: String) -> Self {
        let data = Data(string.utf8)
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data) {
            return envelope.payload
        }
        return (try? JSONDecoder().decode(Self.self, from: data)) ?? .empty
    }
}