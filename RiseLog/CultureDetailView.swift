import SwiftUI
import RiseKit

/// Culture detail: derived-status header, fast logging buttons, and the
/// newest-first timeline with correction affordances (issue #4).
struct CultureDetailView: View {
    @Environment(AppEnvironment.self) private var env
    let cultureId: CultureID

    @State private var capture: CaptureKind?
    @State private var showCorrect = false
    /// Most recently logged event (drives the transient undo banner).
    @State private var lastLogged: Event?

    private var culture: Culture? { env.culture(cultureId) }

    var body: some View {
        List {
            if let culture {
                statusSection(culture)
                logSection
                timelineSection
            }
        }
        .navigationTitle(culture?.name ?? "Culture")
        .sheet(item: $capture) { capture in
            EventCaptureSheet(cultureId: cultureId, kind: capture.kind) { event in
                lastLogged = event
            }
        }
        .confirmationDialog("Correct the latest event?",
                            isPresented: $showCorrect, titleVisibility: .visible) {
            Button("Log again now", role: .none) {
                // Append-only correction: the same payload re-logged at the
                // current time supersedes the original for every derived
                // value. The original row remains in the ledger.
                try? env.correctLatest(in: cultureId)
            }
            .accessibilityIdentifier("detail.correct-confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Rise Log never edits stored events. Logging again now adds a new event that supersedes the latest one.")
        }
        .overlay(alignment: .bottom) { undoBanner }
    }

    // MARK: Sections

    private func statusSection(_ culture: Culture) -> some View {
        let status = env.status(for: cultureId)
        return Section("Status") {
            VStack(alignment: .leading, spacing: 6) {
                Text(status.lastFeedLineText)
                Text(status.risePhaseLineText)
                Text(status.fermentDaysLineText)
                Text(DueWindow.cadenceLine(due: status.dueWindow, now: env.now))
            }
            .font(.callout)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("detail.status")
        }
    }

    private var logSection: some View {
        Section("Log") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                      spacing: 8) {
                captureButton(.feed, title: "Feed", systemImage: "drop")
                captureButton(.riseCheck, title: "Check", systemImage: "eye")
                captureButton(.bottle, title: "Bottle", systemImage: "wineglass")
                captureButton(.bake, title: "Bake", systemImage: "oven")
                captureButton(.discard, title: "Discard", systemImage: "trash")
                captureButton(.note, title: "Note", systemImage: "note.text")
            }
            .padding(.vertical, 4)
            Button("Correct latest event") { showCorrect = true }
                .accessibilityIdentifier("detail.correct")
        }
    }

    private func captureButton(_ kind: Event.Kind, title: String, systemImage: String) -> some View {
        Button {
            capture = CaptureKind(kind: kind)
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("detail.log.\(kind.rawValue)")
    }

    private var timelineSection: some View {
        let events = env.timeline(for: cultureId)
        return Section("Timeline") {
            if events.isEmpty {
                Text("No events logged yet.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("detail.timeline.empty")
            } else {
                ForEach(events, id: \.id) { event in
                    TimelineRow(event: event)
                        .accessibilityIdentifier("detail.row.\(event.id.rawValue)")
                }
            }
        }
    }

    // MARK: Undo banner (shown right after a logging sheet commits)

    @ViewBuilder private var undoBanner: some View {
        if let event = lastLogged,
           case .feed = event.payload {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Feed logged")
                        .font(.callout)
                    Text("Undo adds a matching discard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Undo") {
                    // Append-only undo: reverse the feed by discarding the
                    // same flour amount. Both rows stay in the ledger —
                    // the timeline is the audit trail.
                    try? env.undoFeed(event)
                    lastLogged = nil
                }
                .accessibilityIdentifier("detail.undo")
                Button("Dismiss") { lastLogged = nil }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding()
        }
    }
}

/// One timeline row: time + kind/payload summary (RiseKit-rendered text).
struct TimelineRow: View {
    let event: Event

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(event.occurredAt, format: .dateTime.month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(event.displaySummary)
                .font(.body)
        }
        .accessibilityElement(children: .combine)
        // No static identifier here: duplicated identifiers across rows
        // shadow each other in the XCUITest tree (fleet-proven trap). Row
        // identity comes from the unique `detail.row.<eventID>` the detail
        // view sets outside this row.
    }
}

/// Event capture sheet, one shape per kind. Feed is the 2-tap common
/// case: open → Log Feed (amounts optional).
/// `sheet(item:)` needs an Identifiable payload — the repo's one-field
/// box idiom (Event.Kind is not Identifiable and shouldn't be: a raw
/// string id on the domain enum invites collisions).
struct CaptureKind: Identifiable {
    let kind: Event.Kind
    var id: String { kind.rawValue }
}

struct EventCaptureSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    let cultureId: CultureID
    let kind: Event.Kind
    let onCommit: (Event) -> Void

    @State private var flour = ""
    @State private var water = ""
    @State private var stage: RiseStage = .rising
    @State private var noteText = ""
    @State private var grams = ""

    var body: some View {
        NavigationStack {
            Form {
                switch kind {
                case .feed:
                    TextField("Flour (g, optional)", text: $flour)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("feed.flour")
                    TextField("Water (g, optional)", text: $water)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("feed.water")
                    commitButton("Log Feed", id: "feed.commit") {
                        try env.logFeed(cultureId, flour: gramsValue(flour),
                                        water: gramsValue(water))
                    }
                case .riseCheck:
                    Picker("What does it look like?", selection: $stage) {
                        ForEach(RiseStage.allCases, id: \.self) { s in
                            Text(s.displayName).tag(s)
                        }
                    }
                    .accessibilityIdentifier("check.stage")
                    commitButton("Log Check", id: "check.commit") {
                        try env.logCheck(cultureId, stage: stage)
                    }
                case .bottle:
                    Text("Record when you bottled this batch.")
                        .foregroundStyle(.secondary)
                    commitButton("Log Bottle", id: "bottle.commit") {
                        try env.logBottle(cultureId)
                    }
                case .bake:
                    TextField("Flour used (g, optional)", text: $grams)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("bake.grams")
                    commitButton("Log Bake", id: "bake.commit") {
                        try env.logBake(cultureId, flourUsed: gramsValue(grams))
                    }
                case .discard:
                    TextField("Removed (g, optional)", text: $grams)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("discard.grams")
                    commitButton("Log Discard", id: "discard.commit") {
                        try env.logDiscard(cultureId, removed: gramsValue(grams))
                    }
                case .note:
                    TextField("Note", text: $noteText)
                        .accessibilityIdentifier("note.text")
                    commitButton("Log Note", id: "note.commit") {
                        try env.logNote(cultureId, text: noteText)
                    }
                case .split:
                    // Split creation is lineage UI (later milestone); the
                    // ledger + store already accept split events.
                    Text("Split logging arrives with the lineage UI.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("capture.cancel")
                }
            }
        }
    }

    private var title: String {
        switch kind {
        case .feed: "Log Feed"
        case .riseCheck: "Log Rise Check"
        case .bottle: "Log Bottle"
        case .bake: "Log Bake"
        case .discard: "Log Discard"
        case .note: "Log Note"
        case .split: "Log Split"
        }
    }

    private func commitButton(_ label: String, id: String,
                              _ action: @escaping () throws -> Event?) -> some View {
        Button(label) {
            // A nil result means validation rejected the input (e.g. blank
            // note) — keep the sheet open so the user can fix it.
            if let event = try? action() {
                onCommit(event)
                dismiss()
            }
        }
        .accessibilityIdentifier(id)
    }

    private func gramsValue(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let v = Double(t)
        return (v ?? 0) > 0 ? v : nil
    }
}
