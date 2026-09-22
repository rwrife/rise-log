import Foundation
import Testing

@testable import RiseKit

@Suite("Culture taxonomy")
struct CultureTypeTests {
    @Test("predefined types cover the common ferment families")
    func predefined() {
        #expect(PredefinedCultureType.allCases.count >= 5)
        #expect(CultureType.starter.isPredefined)
        #expect(CultureType.starter.displayName == "Sourdough starter")
    }

    @Test("user-defined types keep their trimmed name")
    func custom() {
        let t = CultureType(customName: "  kefir  ")
        #expect(t?.displayName == "kefir")
        #expect(t?.isPredefined == false)
    }

    @Test("blank user-defined names are rejected, not normalized")
    func blankRejected() {
        #expect(CultureType(customName: "") == nil)
        #expect(CultureType(customName: "   \n ") == nil)
    }

    @Test("a custom name colliding with a predefined display name stays custom")
    func customVsPredefinedDistinct() {
        let impostor = CultureType(customName: "Kombucha")
        #expect(impostor != CultureType.kombucha)
    }

    @Test("cadence rejects non-positive values")
    func cadenceValidation() {
        #expect(FeedingCadence(everyHours: 0) == nil)
        #expect(FeedingCadence(everyHours: -5) == nil)
        #expect(FeedingCadence(everyHours: 12, graceHours: -1) == nil)
        #expect(FeedingCadence(everyHours: 12, graceHours: 0)?.graceHours == 0)
    }
}
