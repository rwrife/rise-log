import Foundation
import Testing

@testable import RiseKit

@Suite("Workspace routing seam")
struct FermentWorkspaceRoutingTests {
    @Test("compact routes single column always")
    func compactRouting() {
        #expect(FermentWorkspaceRouting.route(band: .compact) == .singleColumn)
        #expect(FermentWorkspaceRouting.route(band: .compact, spannedSupportEnabled: true) == .singleColumn)
    }

    @Test("spanned routes single column today; the documented hook flips it to two pane")
    func spannedHook() {
        // Shipped state: the seam's gate is off, so even spanned stays
        // single-column (the app is iPhone-only; a Duo unfold would be
        // regular width).
        #expect(FermentWorkspaceRouting.spannedSupportEnabled == false)
        #expect(FermentWorkspaceRouting.route(band: .spanned) == .singleColumn)
        // Documented hook point for the future iPhone Duo workspace:
        // flipping the gate is the ONLY routing change needed.
        #expect(FermentWorkspaceRouting.route(band: .spanned, spannedSupportEnabled: true) == .twoPane)
    }

    @Test("the seam is the sole layout router in app sources")
    func seamIsSoleRouter() throws {
        // Source-scan proof, runnable on Linux with zero tooling:
        // 1) `horizontalSizeClass` may be read in exactly ONE app file —
        //    FermentWorkspaceLayout.swift — the seam's environment input.
        // 2) That file must route by calling FermentWorkspaceRouting.route.
        // 3) No app source may reference fold/unreleased-SDK API names.
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // RiseKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // RiseKit
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // repo root
        let appDir = repoRoot.appendingPathComponent("RiseLog")
        let swiftFiles = try FileManager.default.contentsOfDirectory(atPath: appDir.path)
            .filter { $0.hasSuffix(".swift") }
        #expect(!swiftFiles.isEmpty, "expected app sources at \(appDir.path)")

        let forbidden = [
            "FoldStatus", "foldStatus", "FoldState", "foldState",
            "HingeAngle", "hingeAngle", "isUnfolded", "unfoldState",
            "SystemFold", "spanningMode",
        ]
        var sizeClassFiles: [String] = []
        for name in swiftFiles {
            let text = try String(
                contentsOf: appDir.appendingPathComponent(name), encoding: .utf8)
            for token in forbidden {
                #expect(!text.contains(token),
                        "forbidden fold/SDK API name '\(token)' in \(name)")
            }
            if text.contains("horizontalSizeClass") {
                sizeClassFiles.append(name)
            }
        }
        #expect(sizeClassFiles == ["FermentWorkspaceLayout.swift"],
                "size-class reading must be confined to the seam file, got \(sizeClassFiles)")

        let seamText = try String(
            contentsOf: appDir.appendingPathComponent("FermentWorkspaceLayout.swift"),
            encoding: .utf8)
        #expect(seamText.contains("FermentWorkspaceRouting.route"),
                "the seam file must delegate to the domain routing function")
    }
}
