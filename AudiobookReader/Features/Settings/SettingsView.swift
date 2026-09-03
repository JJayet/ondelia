import SwiftUI

struct SettingsView: View {
    // State is internal (not private) so the section extensions in
    // SettingsView+Sections.swift / SettingsView+TranscriptionSection.swift can drive it.
    @StateObject var themeManager = ThemeManager.shared
    @StateObject var statistics = ReadingStatistics.shared
    @StateObject var whisperManager = WhisperTranscriptionManager.shared
    @Environment(\.dismiss) private var dismiss
    @State var showingGoalEditor = false
    @State var tempGoal: Double = 0
    @State var showModelDownloadConfirm = false
    @State var pendingWhisperModel: WhisperModel? = nil
    @State var showResetStatsConfirm = false

    var body: some View {
        NavigationStack {
            List {
                appearanceSection
                playbackSection
                transcriptionSection
                goalsSection
                statisticsSection
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
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.primaryBackground)
            .tint(themeManager.accentColor.color)
            .listRowBackground(Color.clear)
        }
        .alert(
            NSLocalizedString("Download Model?", comment: "Whisper model download confirm title"),
            isPresented: $showModelDownloadConfirm
        ) {
            Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {
                pendingWhisperModel = nil
            }
            Button(NSLocalizedString("Download", comment: "Download button")) {
                if let model = pendingWhisperModel {
                    Task { try? await whisperManager.switchModel(to: model) }
                }
                pendingWhisperModel = nil
            }
        } message: {
            Text(
                String(
                    format: NSLocalizedString(
                        "Download %@ model for offline transcription?",
                        comment: "Whisper download confirm message"
                    ),
                    pendingWhisperModel?.displayName ?? ""
                )
            )
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
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        .tint(themeManager.accentColor.color)
    }
}

#Preview("Settings") {
    SettingsView()
}
