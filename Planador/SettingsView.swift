import SwiftUI
import UniformTypeIdentifiers

struct BackupFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var bytes: Data

    init(bytes: Data) { self.bytes = bytes }
    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.bytes = bytes
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: bytes)
    }
}

private struct PendingRestore: Identifiable {
    let id = UUID()
    let filename: String
    let data: AppData
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var exporting = false
    @State private var importing = false
    @State private var backup: BackupFile?
    @State private var pendingRestore: PendingRestore?
    @State private var status: String?
    @State private var enablingNotifications = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Settings").font(.system(size: 26, design: .serif))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Stepper(value: Binding(
                get: { store.data.timerSettings.workMinutes },
                set: { store.setWorkMinutes($0) }
            ), in: 5...120, step: 5) {
                HStack {
                    Text("Focus session")
                    Spacer()
                    Text("\(store.data.timerSettings.workMinutes) min").foregroundStyle(Theme.muted).monospacedDigit()
                }
            }
            .accessibilityLabel("Focus session length")
            Stepper(value: Binding(
                get: { store.data.timerSettings.breakMinutes },
                set: { store.setBreakMinutes($0) }
            ), in: 1...30) {
                HStack {
                    Text("Break")
                    Spacer()
                    Text("\(store.data.timerSettings.breakMinutes) min").foregroundStyle(Theme.muted).monospacedDigit()
                }
            }
            .accessibilityLabel("Break length")
            Text("Duration changes apply to the next timer. A chime marks each timer's end.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
            Toggle("Show timer completion notifications", isOn: Binding(
                get: { store.data.notificationsEnabled },
                set: { enabled in
                    enablingNotifications = true
                    Task {
                        await store.setNotificationsEnabled(enabled)
                        enablingNotifications = false
                    }
                }
            ))
            .disabled(enablingNotifications)
            Divider()
            Text("Backup and restore").font(.headline)
            Text("Export tasks, notes, focus sessions, and timer settings. Restored timers stay paused.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
            HStack {
                Button("Export backup…") {
                    do {
                        backup = BackupFile(bytes: try store.backupData())
                        exporting = true
                    } catch { store.errorMessage = "Backup could not be created: \(error.localizedDescription)" }
                }
                Button("Restore backup…") { importing = true }
            }
            if let status {
                Text(status).font(.system(size: 12)).textSelection(.enabled)
            }
            Spacer(minLength: 0)
            Text("Tasks and focus time are saved on this Mac. The menu-bar timer stays available when the window is closed.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
        .padding(28).frame(width: 480, height: 480)
        .fileExporter(isPresented: $exporting, document: backup, contentType: .json,
                      defaultFilename: store.backupFilename) { result in
            switch result {
            case .success: status = "Backup exported."
            case .failure(let error): store.errorMessage = "Backup export failed: \(error.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let restored = try store.readBackup(Data(contentsOf: url))
                pendingRestore = PendingRestore(filename: url.lastPathComponent, data: restored)
            } catch { store.errorMessage = "Backup could not be opened: \(error.localizedDescription)" }
        }
        .alert("Replace current data?", isPresented: Binding(
            get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }
        ), presenting: pendingRestore) { restore in
            Button("Cancel", role: .cancel) { pendingRestore = nil }
            Button("Restore backup", role: .destructive) {
                do {
                    let recovery = try store.restoreBackup(restore.data)
                    status = "Backup restored. Previous data saved at \(recovery.path)"
                } catch { store.errorMessage = "Restore failed. Current data was kept: \(error.localizedDescription)" }
                pendingRestore = nil
            }
        } message: { restore in
            Text("\(restore.filename) contains \(restore.data.tasks.count) tasks and \(restore.data.sessions.count) focus sessions. This replaces your current tasks and history. A recovery copy will be saved first.")
        }
        .alert("Planador needs attention", isPresented: Binding(
            get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } }
        )) { Button("OK") { store.errorMessage = nil } } message: {
            Text(store.errorMessage ?? "An unknown error occurred.")
        }
    }
}
