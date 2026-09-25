import SwiftUI
import RiseKit

/// Root of the jar-wall → detail workflow (issue #4).
///
/// NavigationStack (not NavigationSplitView): iPhone-only, single column,
/// and the split variant would push detail over the wall at compact width
/// (a fleet-known XCUITest trap). The Duo seam (`FermentWorkspaceLayout`,
/// issue #5) will wrap this stack, not rewrite it.
struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showCreate = false

    var body: some View {
        NavigationStack {
            JarWallView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showCreate = true
                        } label: {
                            Label("Add culture", systemImage: "plus")
                                .accessibilityIdentifier("wall.add-culture")
                        }
                    }
                }
                .sheet(isPresented: $showCreate) {
                    CreateCultureSheet()
                }
        }
    }
}

/// The jar wall: every culture with its derived badge, plus the empty
/// state that offers the sample culture or starting empty.
struct JarWallView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Group {
            if env.cultures.isEmpty {
                emptyState
            } else {
                wall
            }
        }
        .navigationTitle("Rise Log")
        .navigationDestination(for: CultureID.self) { id in
            CultureDetailView(cultureId: id)
        }
        .refreshable { env.reload() }
    }

    private var wall: some View {
        List(env.cultures, id: \.id) { culture in
            NavigationLink(value: culture.id) {
                CultureRow(culture: culture)
            }
            .accessibilityIdentifier("wall.row.\(culture.id.rawValue)")
        }
        .accessibilityIdentifier("wall.list")
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("No jars yet")
                .font(.title2)
                .accessibilityAddTraits(.isHeader)
            Text("Add your first culture, or try a sample starter with a few logged events.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add sample starter") {
                try? env.addSample()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("wall.sample")
            Text("Or tap + to create your own culture.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("wall.empty")
    }
}

/// One jar-wall row: name + derived badge. The badge line is the pure
/// `CultureStatus.badgeText` (RiseKit) — wording is unit-tested there.
struct CultureRow: View {
    @Environment(AppEnvironment.self) private var env
    let culture: Culture

    var body: some View {
        let status = env.status(for: culture.id)
        VStack(alignment: .leading, spacing: 4) {
            Text(culture.name)
                .font(.headline)
                .accessibilityIdentifier("row.name.\(culture.id.rawValue)")
            Text(status.badgeText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityLabel(status.badgeAccessibilityLabel)
                .accessibilityIdentifier("row.badge.\(culture.id.rawValue)")
        }
        // Do NOT merge the row into one element: the journey needs the
        // badge separately (badge-updates assertion), and SwiftUI's
        // .combine on a NavigationLink label reliably hides children.
        .padding(.vertical, 2)
    }
}

/// Create-culture sheet: trimmed name + type picker (predefined + custom).
struct CreateCultureSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var predefined: PredefinedCultureType = .starter
    @State private var useCustom = false
    @State private var customName = ""

    private var canSave: Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return false }
        if useCustom {
            return customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? false : true
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Jar name", text: $name)
                    .accessibilityIdentifier("create.name")
                Toggle("Custom type", isOn: $useCustom)
                    .accessibilityIdentifier("create.custom")
                if useCustom {
                    TextField("Type name", text: $customName)
                        .accessibilityIdentifier("create.custom-name")
                } else {
                    Picker("Type", selection: $predefined) {
                        ForEach(PredefinedCultureType.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .accessibilityIdentifier("create.type")
                }
            }
            .navigationTitle("New culture")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("create.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let type: CultureType?
                        if useCustom {
                            type = CultureType(customName: customName)
                        } else {
                            switch predefined {
                            case .starter: type = .starter
                            case .kombucha: type = .kombucha
                            case .kimchi: type = .kimchi
                            case .yogurt: type = .yogurt
                            case .vinegar: type = .vinegar
                            }
                        }
                        if let type, (try? env.createCulture(name: name, type: type)) != nil {
                            dismiss()
                        }
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("create.save")
                }
            }
        }
    }
}
