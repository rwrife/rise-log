import Foundation
import RiseKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Backup, restore, and CSV export view (issue #6).
///
/// Exports:
/// - Versioned JSON archive (Rise Log persistent state).
/// - Separate CSV ledger view of all events.
/// Both use the system share/save panel (`UIActivityViewController`), allowing
/// saving to the Files app, AirDrop, etc.
///
/// Import:
/// - Picks an archive via `.fileImporter`.
/// - Validates schema version and structure.
/// - Previews the replacement diff (cultures/events added/removed).
/// - Replaces ONLY after explicit user confirmation (destructive role).
/// - No silent merge path exists.
struct BackupView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var shareItems: [URL]?
    @State private var showFilePicker = false
    @State private var pendingRestore: PendingRestore?
    @State private var alertMessage: BackupAlert?

    struct BackupAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let isError: Bool
    }

    struct PendingRestore: Identifiable {
        let id = UUID()
        let archive: BackupArchive
        let preview: BackupRestorePreview
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Export") {
                    Button {
                        exportBackupArchive()
                    } label: {
                        Label("Export JSON archive", systemImage: "arrow.up.doc")
                    }
                    .accessibilityIdentifier("backup.export-json")

                    Button {
                        exportLedgerCSV()
                    } label: {
                        Label("Export CSV event ledger", systemImage: "tablecells")
                    }
                    .accessibilityIdentifier("backup.export-csv")

                    Text("Files are written locally and handed to the system share sheet. Save them to the Files app or your preferred storage.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Restore") {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Restore from backup…", systemImage: "arrow.down.doc")
                    }
                    .accessibilityIdentifier("backup.restore")

                    Text("Restoring replaces all current cultures and events with the backup contents after showing a preview diff. No silent merge path exists.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Data & Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("backup.done")
                }
            }
            .sheet(item: Binding(
                get: { shareItems.map(SharePayload.init) },
                set: { shareItems = $0?.urls }
            )) { payload in
                ActivityShareSheet(items: payload.urls)
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
            .sheet(item: $pendingRestore) { pending in
                RestorePreviewSheet(pending: pending) {
                    executeRestore(pending.archive)
                }
            }
            .alert(item: $alertMessage) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .accessibilityIdentifier("screen.backup")
    }

    // MARK: - Actions

    private func exportBackupArchive() {
        do {
            let data = try env.makeBackupData()
            let filename = "riselog-backup-\(dateStamp()).json"
            guard let url = writeTempFile(data: data, filename: filename) else {
                alertMessage = BackupAlert(title: "Export failed", message: "Could not create temporary export file.", isError: true)
                return
            }
            shareItems = [url]
        } catch {
            alertMessage = BackupAlert(title: "Export failed", message: error.localizedDescription, isError: true)
        }
    }

    private func exportLedgerCSV() {
        do {
            let csv = try env.makeLedgerCSV()
            guard let data = csv.data(using: .utf8) else {
                alertMessage = BackupAlert(title: "Export failed", message: "Failed to encode CSV text.", isError: true)
                return
            }
            let filename = "riselog-ledger-\(dateStamp()).csv"
            guard let url = writeTempFile(data: data, filename: filename) else {
                alertMessage = BackupAlert(title: "Export failed", message: "Could not create temporary CSV file.", isError: true)
                return
            }
            shareItems = [url]
        } catch {
            alertMessage = BackupAlert(title: "Export failed", message: error.localizedDescription, isError: true)
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            alertMessage = BackupAlert(title: "File selection failed", message: error.localizedDescription, isError: true)
        case .success(let urls):
            guard let url = urls.first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try Data(contentsOf: url)
                let (archive, preview) = try env.previewRestore(data: data)
                pendingRestore = PendingRestore(archive: archive, preview: preview)
            } catch {
                alertMessage = BackupAlert(title: "Cannot restore backup", message: error.localizedDescription, isError: true)
            }
        }
    }

    private func executeRestore(_ archive: BackupArchive) {
        do {
            try env.restore(archive: archive)
            alertMessage = BackupAlert(title: "Restore complete", message: "Your ferment log has been restored from the backup.", isError: false)
        } catch {
            alertMessage = BackupAlert(title: "Restore failed", message: error.localizedDescription, isError: true)
        }
    }

    // MARK: - Temp file writing

    private func writeTempFile(data: Data, filename: String) -> URL? {
        let exportDir = FileManager.default.temporaryDirectory.appendingPathComponent("RiseLogExports", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
            let fileURL = exportDir.appendingPathComponent(filename)
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }

    private func dateStamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: env.now)
    }

    private struct SharePayload: Identifiable {
        let urls: [URL]
        var id: String { urls.map(\.absoluteString).joined(separator: "|") }
    }
}

/// Modal preview diff sheet displayed before replacing store data.
struct RestorePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let pending: BackupView.PendingRestore
    let onConfirm: () -> Void

    @State private var showConfirmDialog = false

    var body: some View {
        NavigationStack {
            List {
                Section("Warning") {
                    Label(
                        "Restoring will completely replace your current jars and events. Existing data cannot be merged.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    .font(.subheadline)
                }

                Section("Cultures summary") {
                    HStack {
                        Text("Current jars")
                        Spacer()
                        Text("\(pending.preview.currentCultureCount)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Backup jars")
                        Spacer()
                        Text("\(pending.preview.incomingCultureCount)")
                            .bold()
                    }

                    if !pending.preview.addedCultureNames.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Added jars:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(pending.preview.addedCultureNames, id: \.self) { name in
                                Text("+ \(name)")
                                    .font(.subheadline)
                                    .foregroundStyle(.green)
                            }
                        }
                    }

                    if !pending.preview.removedCultureNames.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Removed jars (will be deleted):")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(pending.preview.removedCultureNames, id: \.self) { name in
                                Text("- \(name)")
                                    .font(.subheadline)
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    if !pending.preview.keptCultureNames.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Replaced jars:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(pending.preview.keptCultureNames, id: \.self) { name in
                                Text("• \(name)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Events summary") {
                    HStack {
                        Text("Current logged events")
                        Spacer()
                        Text("\(pending.preview.currentEventCount)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Backup events")
                        Spacer()
                        Text("\(pending.preview.incomingEventCount)")
                            .bold()
                    }
                    HStack {
                        Text("New events added")
                        Spacer()
                        Text("+\(pending.preview.addedEventCount)")
                            .foregroundStyle(.green)
                    }
                    HStack {
                        Text("Current events removed")
                        Spacer()
                        Text("-\(pending.preview.removedEventCount)")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showConfirmDialog = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Replace All Data")
                                .bold()
                            Spacer()
                        }
                    }
                    .accessibilityIdentifier("restore.confirm-replace-button")
                }
            }
            .navigationTitle("Restore Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("restore.cancel")
                }
            }
            .confirmationDialog(
                "Are you sure you want to replace all current data?",
                isPresented: $showConfirmDialog,
                titleVisibility: .visible
            ) {
                Button("Replace All Data", role: .destructive) {
                    dismiss()
                    onConfirm()
                }
                .accessibilityIdentifier("restore.final-confirm")

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action replaces all your existing jars, notes, and feeding history with the backup. This cannot be undone.")
            }
            .accessibilityIdentifier("screen.restore-preview")
        }
    }
}

/// Thin UIKit wrapper for system share sheet.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
