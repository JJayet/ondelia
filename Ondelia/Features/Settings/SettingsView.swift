import SwiftUI

struct SettingsView: View {
    // State is internal (not private) so the section extensions in
    // SettingsView+Sections.swift can drive it.
    @Bindable var themeManager = ThemeManager.shared
    let statistics = ReadingStatistics.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ChapterScrubber.showChapterTimesKey) var showChapterTimes = true
    @AppStorage("playback.bookOpeningDelayMS") var bookOpeningDelayMS = 200
    @AppStorage(GlobalAudioManager.autoSleepTimerKey) var autoSleepTimer = false
    @AppStorage("library.gridColumns") var gridColumns = 2
    @State var appIcon = UIApplication.shared.alternateIconName ?? "Day"
    @AppStorage(AudiobookManager.autoSeriesCollectionsKey) var autoSeriesCollections = true
    @AppStorage(CollectionGroup.showMissingKey) var showMissingSeriesBooks = true
    @AppStorage(GlobalAudioManager.deleteOnCompletionKey) var deleteOnCompletion = false
    @State var showingGoalEditor = false
    @State var tempGoal: Double = 0
    @State var showResetStatsConfirm = false
    @State var showingBackupRestore = false
    @State var showingStorage = false
    @AppStorage(SwiftDataController.iCloudSyncKey) var iCloudSync = true
    /// Whole library folder, shown beside the Storage row. Recomputed each time Settings opens.
    @State var storageBytes: Int64?
    @AppStorage(OnboardingView.completedKey) var onboardingCompleted = false
    @AppStorage(AppTips.resetPendingKey) var tipsResetPending = false

    var body: some View {
        NavigationStack {
            // iPhone Duo around its fold (design 10a): two columns starting level, each group
            // whole on one side.
            FoldSplit {
                settingsColumn {
                    appearanceSection
                    librarySection
                    goalsSection
                    dataSection
                }
            } secondary: {
                settingsColumn {
                    playbackSection
                    integrationsSection
                    WatchSettingsSection()
                    aboutSection
                }
            } fallback: {
                // One column everywhere else; a wide window centres it instead of stretching rows.
                settingsColumn(maxWidth: 640) {
                    appearanceSection
                    librarySection
                    playbackSection
                    goalsSection
                    integrationsSection
                    WatchSettingsSection()
                    dataSection
                    // TipJarSection() // Hidden until the products exist in App Store Connect.
                    aboutSection
                }
            }
            .navigationTitle(NSLocalizedString("Settings", comment: "Settings view title"))
            .navigationBarTitleDisplayMode(.large)
            .alert(NSLocalizedString("Monthly Goal", comment: "Monthly goal alert title"), isPresented: $showingGoalEditor) {
                TextField(NSLocalizedString("Hours", comment: "Hours text field placeholder"), value: $tempGoal, format: .number)
                    .keyboardType(.decimalPad)

                Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) { withHapticFeedback {} }
                Button(NSLocalizedString("Save", comment: "Save button")) {
                    withHapticFeedback { statistics.updateMonthlyGoal(tempGoal * 3600) } // Convert hours to seconds
                }
            } message: {
                Text(NSLocalizedString("Set your monthly listening goal in hours", comment: "Monthly goal alert message"))
            }
            .sheet(isPresented: $showingBackupRestore) { BackupRestoreView() }
            .sheet(isPresented: $showingStorage) { StorageView() }
            .task {
                let url = AudiobookModel.libraryFolderURL
                storageBytes = await Task.detached { StorageUsage.bytes(at: url) }.value
            }
            .scrollContentBackground(.hidden)
            .background(TintedBackground(intensity: 0.6))
        }
        .alert(
            NSLocalizedString("Reset Stats?", comment: "Reset stats confirm title"),
            isPresented: $showResetStatsConfirm
        ) {
            Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) { withHapticFeedback {} }
            Button(NSLocalizedString("Reset", comment: "Reset button"), role: .destructive) {
                withHapticFeedback { statistics.resetAll() }
            }
        } message: {
            Text(NSLocalizedString("This will clear your listening time, streaks, and monthly progress. Your books, goals, and earned Milestones remain.", comment: "Reset stats confirm message"))
        }
    }

    private func settingsColumn(maxWidth: CGFloat? = nil, @ViewBuilder _ sections: () -> some View) -> some View {
        ScrollView {
            VStack(spacing: 22) { sections() }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
        }
    }
}

#Preview("Settings") {
    SettingsView()
}
