import SwiftUI

/// Lists the store copies `DatabaseBackupService` writes, and puts one back.
///
/// Restoring cannot take effect in the running process — the container is already open on the
/// file being replaced — so this is honest about needing a relaunch rather than pretending.
struct BackupRestoreView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var backups: [(url: URL, date: Date)] = []
    @State private var pendingRestore: URL?
    @State private var errorMessage: String?
    @State private var didRestore = false

    var body: some View {
        NavigationStack {
            List {
                if backups.isEmpty {
                    ContentUnavailableView(
                        NSLocalizedString("No Backups Yet", comment: "Empty backup list title"),
                        systemImage: "externaldrive",
                        description: Text(NSLocalizedString(
                            "A copy of your library is kept once a day.",
                            comment: "Empty backup list description"
                        ))
                    )
                } else {
                    Section {
                        ForEach(backups, id: \.url) { backup in
                            Button {
                                withHapticFeedback { pendingRestore = backup.url }
                            } label: {
                                Label(
                                    backup.date.formatted(date: .abbreviated, time: .shortened),
                                    systemImage: "clock.arrow.circlepath"
                                )
                            }
                        }
                    } footer: {
                        Text(NSLocalizedString(
                            "Restoring replaces your current progress, bookmarks and chapters with the ones in the backup. Your audio files are not touched.",
                            comment: "Backup restore explanation"
                        ))
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Restore Backup", comment: "Restore backup view title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Done", comment: "Done button")) { withHapticFeedback { dismiss() } }
                }
            }
        }
        .onAppear { backups = DatabaseBackupService.availableBackups() }
        .confirmationDialog(
            NSLocalizedString("Restore this backup?", comment: "Restore confirmation title"),
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Restore", comment: "Restore button"), role: .destructive) {
                withHapticFeedback { restore() }
            }
            Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) { withHapticFeedback {} }
        }
        .alert(
            NSLocalizedString("Restored", comment: "Restore success alert title"),
            isPresented: $didRestore
        ) {
            Button(NSLocalizedString("OK", comment: "OK button")) { withHapticFeedback { dismiss() } }
        } message: {
            Text(NSLocalizedString(
                "Quit and reopen the app to finish restoring your library.",
                comment: "Restore success alert message"
            ))
        }
        .alert(
            NSLocalizedString("Restore Failed", comment: "Restore failure alert title"),
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
            presenting: errorMessage
        ) { _ in
            Button(NSLocalizedString("OK", comment: "OK button")) { withHapticFeedback {} }
        } message: { message in
            Text(message)
        }
    }

    private func restore() {
        guard let backup = pendingRestore,
              let storeURL = SwiftDataController.shared.container.configurations.first?.url else {
            return
        }
        pendingRestore = nil
        do {
            try DatabaseBackupService.restore(backup, storeURL: storeURL)
            didRestore = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    BackupRestoreView()
}
