import Foundation
import Testing

@testable import RiseKit

@Suite("Workspace continuity state")
struct WorkspaceContinuityStateTests {
    @Test("empty state has nil selection and no anchors")
    func emptyState() {
        let state = WorkspaceContinuityState.empty
        #expect(state.isEmpty)
        #expect(state.selectedCultureID == nil)
        #expect(state.timelineAnchorByCultureID.isEmpty)
    }

    @Test("round-trip JSON serialization")
    func jsonRoundTrip() throws {
        var state = WorkspaceContinuityState()
        state.setSelectedCultureID("culture-1")
        state.setTimelineAnchor("event-99", for: "culture-1")
        state.setTimelineAnchor("event-42", for: "culture-2")

        let json = try state.toJSONString()
        let decoded = try WorkspaceContinuityState.fromJSONString(json)
        #expect(decoded == state)
        #expect(decoded.selectedCultureID == "culture-1")
        #expect(decoded.timelineAnchor(for: "culture-1") == "event-99")
        #expect(decoded.timelineAnchor(for: "culture-2") == "event-42")
    }

    @Test("fromStorageOrEmpty handles nil, empty, and malformed strings safely")
    func tolerantStorageParsing() {
        #expect(WorkspaceContinuityState.fromStorageOrEmpty(nil) == .empty)
        #expect(WorkspaceContinuityState.fromStorageOrEmpty("") == .empty)
        #expect(WorkspaceContinuityState.fromStorageOrEmpty("not-json") == .empty)
    }

    @Test("envelope parsing decodes versioned payloads")
    func envelopeDecoding() throws {
        var state = WorkspaceContinuityState()
        state.setSelectedCultureID("sample-culture")
        state.setTimelineAnchor("sample-event", for: "sample-culture")

        let envelopeJSON = try state.toVersionedJSONString()
        let decoded = WorkspaceContinuityState.fromAnyJSONString(envelopeJSON)
        #expect(decoded == state)
    }

    @Test("pruning removes missing culture ids")
    func pruningMissingCultures() {
        var state = WorkspaceContinuityState()
        state.setSelectedCultureID("c1")
        state.setTimelineAnchor("e1", for: "c1")
        state.setTimelineAnchor("e2", for: "c2")

        state.prune(keepingCultureIDs: ["c2"])
        #expect(state.selectedCultureID == nil)
        #expect(state.timelineAnchor(for: "c1") == nil)
        #expect(state.timelineAnchor(for: "c2") == "e2")
    }

    @Test("normalization trims oldest anchors beyond capacity")
    func normalizationCap() {
        var state = WorkspaceContinuityState()
        for i in 0..<10 {
            state.setTimelineAnchor("e\(i)", for: "c\(String(format: "%02d", i))")
        }
        let normalized = state.normalizedForStorage(maxAnchors: 5)
        #expect(normalized.timelineAnchorByCultureID.count == 5)
        // Kept newest 5 by dropping smallest keys (c00..c04)
        #expect(normalized.timelineAnchor(for: "c00") == nil)
        #expect(normalized.timelineAnchor(for: "c09") == "e9")
    }
}
