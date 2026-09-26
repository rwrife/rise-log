import SwiftUI
import RiseKit

/// The single layout adaptation seam for Rise Log (issue #5).
///
/// Dual-screen (iPhone Duo) value story: persistent jar-wall control surface
/// beside a detailed timeline pane. Today this is a DOCUMENTED DESIGN TARGET:
/// all composition funnels through this seam, single-pane flow is preserved
/// on current iPhone hardware (`TARGETED_DEVICE_FAMILY = 1`), and no fold/
/// unreleased-SDK APIs are referenced.
///
/// This view is the ONLY file in the app target allowed to read
/// `horizontalSizeClass`, and the ONLY file that composes the jar wall with
/// the culture detail view. A Linux-run source-scan test
/// (`FermentWorkspaceRoutingTests.seamIsSoleRouter`) enforces this at CI.
struct FermentWorkspaceLayout: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @SceneStorage("riselog.workspace.continuity")
    private var continuityStorage: String = ""

    @State private var continuityState: WorkspaceContinuityState = .empty
    @State private var path: [CultureID] = []

    private var band: WorkspaceBand {
        horizontalSizeClass == .compact ? .compact : .spanned
    }

    private var presentation: WorkspacePresentation {
        FermentWorkspaceRouting.route(band: band)
    }

    var body: some View {
        Group {
            switch presentation {
            case .singleColumn:
                singleColumnLayout
            case .twoPane:
                twoPaneLayout
            }
        }
        .onAppear {
            restoreContinuity()
        }
        .onChange(of: continuityStorage) { _, newValue in
            if !newValue.isEmpty {
                continuityState = WorkspaceContinuityState.fromAnyJSONString(newValue)
            }
        }
    }

    // MARK: - Single Column Layout (Shipped iPhone Flow)

    private var singleColumnLayout: some View {
        NavigationStack(path: $path) {
            JarWallView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        AddCultureButton()
                    }
                }
                .navigationDestination(for: CultureID.self) { id in
                    CultureDetailView(
                        cultureId: id,
                        initialAnchorID: continuityState.timelineAnchor(for: id.rawValue),
                        onTimelineScroll: { eventID in
                            recordAnchor(eventID: eventID, for: id)
                        }
                    )
                }
        }
        .onChange(of: path) { _, newPath in
            if let selected = newPath.last {
                recordSelection(selected)
            } else {
                recordSelection(nil)
            }
        }
    }

    // MARK: - Two Pane Layout (Duo Hook Point, Gate-Guarded)

    private var twoPaneLayout: some View {
        HStack(spacing: 0) {
            NavigationStack {
                JarWallView(onSelect: { id in
                    recordSelection(id)
                })
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            AddCultureButton()
                        }
                    }
            }
            .frame(minWidth: 320, idealWidth: 380, maxWidth: 440)
            .accessibilityIdentifier("workspace.pane.wall")

            Divider()

            Group {
                if let selectedID = selectedCultureID {
                    NavigationStack {
                        CultureDetailView(
                            cultureId: selectedID,
                            initialAnchorID: continuityState.timelineAnchor(for: selectedID.rawValue),
                            onTimelineScroll: { eventID in
                                recordAnchor(eventID: eventID, for: selectedID)
                            }
                        )
                    }
                } else {
                    twoPanePlaceholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("workspace.pane.detail")
        }
    }

    private var twoPanePlaceholder: some View {
        VStack(spacing: 12) {
            Text("Select a jar")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Pick a starter or culture from the jar wall to view its timeline.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Continuity Helpers

    private var selectedCultureID: CultureID? {
        if let raw = continuityState.selectedCultureID {
            return CultureID(rawValue: raw)
        }
        return nil
    }

    private func recordSelection(_ id: CultureID?) {
        continuityState.setSelectedCultureID(id?.rawValue)
        persistContinuity()
    }

    private func recordAnchor(eventID: String, for id: CultureID) {
        continuityState.setTimelineAnchor(eventID, for: id.rawValue)
        persistContinuity()
    }

    private func persistContinuity() {
        if let value = continuityState.sceneStorageValueOrNilIfEmpty {
            continuityStorage = value
        } else {
            continuityStorage = ""
        }
    }

    private func restoreContinuity() {
        continuityState = WorkspaceContinuityState.fromStorageOrEmpty(continuityStorage)
        // If single column and an id was saved, restore navigation path if culture exists
        if presentation == .singleColumn,
           let raw = continuityState.selectedCultureID,
           path.isEmpty {
            let id = CultureID(rawValue: raw)
            if env.culture(id) != nil {
                path = [id]
            }
        }
    }
}

/// The "+" toolbar button for adding a new culture.
struct AddCultureButton: View {
    @State private var showCreate = false

    var body: some View {
        Button {
            showCreate = true
        } label: {
            Label("Add culture", systemImage: "plus")
                .accessibilityIdentifier("wall.add-culture")
        }
        .sheet(isPresented: $showCreate) {
            CreateCultureSheet()
        }
    }
}
