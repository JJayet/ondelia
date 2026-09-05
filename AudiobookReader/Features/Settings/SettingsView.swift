import SwiftUI
import Speech

struct SettingsView: View {
    // State is internal (not private) so the section extensions in
    // SettingsView+Sections.swift / SettingsView+TranscriptionSection.swift can drive it.
    @Bindable var themeManager = ThemeManager.shared
    let statistics = ReadingStatistics.shared
    let speechManager = SpeechTranscriptionManager.shared
    @Environment(\.dismiss) private var dismiss
    @State var showingGoalEditor = false
    @State var tempGoal: Double = 0
    /// nil until the first asset check answers; drives the language-model row.
    @State var assetStatus: AssetInventory.Status? = nil
    @State var showResetStatsConfirm = false
    @State var showingBackupRestore = false

    var body: some View {
        NavigationStack {
            List {
                appearanceSection
                playbackSection
                transcriptionSection
                goalsSection
                dataSection
                aboutSection
            }
            .navigationTitle(NSLocalizedString("Settings", comment: "Settings view title"))
            .navigationBarTitleDisplayMode(.inline)
            .alert(NSLocalizedString("Monthly Goal", comment: "Monthly goal alert title"), isPresented: $showingGoalEditor) {
                TextField(NSLocalizedString("Hours", comment: "Hours text field placeholder"), value: $tempGoal, format: .number)
                    .keyboardType(.decimalPad)

                Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {}
                Button(NSLocalizedString("Save", comment: "Save button")) {
                    statistics.updateMonthlyGoal(tempGoal * 3600) // Convert hours to seconds
                }
            } message: {
                Text(NSLocalizedString("Set your monthly listening goal in hours", comment: "Monthly goal alert message"))
            }
            .sheet(isPresented: $showingBackupRestore) { BackupRestoreView() }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.primaryBackground)
                .listRowBackground(Color.clear)
        }
        .alert(
            NSLocalizedString("Reset Stats?", comment: "Reset stats confirm title"),
            isPresented: $showResetStatsConfirm
        ) {
            Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {}
            Button(NSLocalizedString("Reset", comment: "Reset button"), role: .destructive) {
                statistics.resetAll()
            }
        } message: {
            Text(NSLocalizedString("This will clear your listening time, streaks, and monthly progress. Your books and goals remain.", comment: "Reset stats confirm message"))
        }
    }
}

#Preview("Settings") {
    SettingsView()
}
