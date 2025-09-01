import SwiftUI

struct SettingsView: View {
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var statistics = ReadingStatistics()
    @StateObject private var whisperManager = WhisperTranscriptionManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingGoalEditor = false
    @State private var tempGoal: Double = 0
    @State private var showModelDownloadConfirm = false
    @State private var pendingWhisperModel: WhisperModel? = nil
    @State private var showResetStatsConfirm = false
    
    var body: some View {
        NavigationStack {
            List {
                // Appearance Section
                Section(NSLocalizedString("Appearance", comment: "Settings section: Appearance")) {
                    HStack {
                        Label(NSLocalizedString("Theme", comment: "Theme setting label"), systemImage: "paintbrush")
                            .foregroundColor(.primaryText)
                        Spacer()
                        Picker("", selection: $themeManager.currentTheme) {
                            ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                                Text(theme.displayName)
                                    .foregroundColor(.primaryText)
                                    .tag(theme)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .onChange(of: themeManager.currentTheme) { _, newTheme in
                            themeManager.setTheme(newTheme)
                        }
                    }
                    .modifier(SettingsRowCard())
                    
                    HStack {
                        Label(NSLocalizedString("Accent Color", comment: "Accent color setting label"), systemImage: "circle.fill")
                            .foregroundColor(themeManager.accentColor.color)
                        Spacer()
                        Picker("", selection: $themeManager.accentColor) {
                            ForEach(AccentColor.allCases, id: \.rawValue) { color in
                                Label(color.displayName, systemImage: "circle.fill")
                                    .tint(color.color)
                                    .tag(color)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(MenuPickerStyle())
                        .onChange(of: themeManager.accentColor) { _, newColor in
                            themeManager.setAccentColor(newColor)
                        }
                    }
                    .modifier(SettingsRowCard())
                }
                
                // Playback Section
                Section(NSLocalizedString("Playback", comment: "Settings section: Playback")) {
                    HStack {
                        Label("", systemImage: "goforward")
                            .foregroundColor(.primaryText)
                        Spacer()
                        Picker(NSLocalizedString("Skip Interval", comment: "Skip interval picker label"), selection: $themeManager.skipInterval) {
                            ForEach(SkipInterval.allCases, id: \.rawValue) { interval in
                                Text(interval.displayName)
                                    .foregroundColor(.primaryText)
                                    .tag(interval)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .onChange(of: themeManager.skipInterval) { _, newInterval in
                            themeManager.setSkipInterval(newInterval)
                        }
                    }
                    .modifier(SettingsRowCard())
                }
                
                // Transcription Section
                Section(NSLocalizedString("Transcription", comment: "Settings section: Transcription")) {
                    VStack(alignment: .leading) {
                        HStack {
                            Label(NSLocalizedString("WhisperKit Model", comment: "WhisperKit model setting label"), systemImage: "brain")
                                .foregroundColor(.primaryText)
                            Spacer()
                            Picker("", selection: $themeManager.whisperModel) {
                                ForEach(WhisperModel.allCases, id: \.rawValue) { model in
                                    VStack(alignment: .leading) {
                                        Text(model.displayName)
                                            .font(.body)
                                            .foregroundColor(.primaryText)
                                        HStack {
                                            Text(model.sizeDescription)
                                                .font(.caption)
                                                .foregroundColor(.secondaryText)
                                            Text("•")
                                                .font(.caption)
                                                .foregroundColor(.secondaryText)
                                            HStack(spacing: 2) {
                                                ForEach(0..<5) { index in
                                                    Image(systemName: index < model.accuracyRating ? "star.fill" : "star")
                                                        .font(.system(size: 8))
                                                        .foregroundColor(index < model.accuracyRating ? .yellow : .secondaryText)
                                                }
                                            }
                                        }
                                    }
                                    .tag(model)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .onChange(of: themeManager.whisperModel) { _, newModel in
                                themeManager.updateWhisperModel(newModel)
                                if themeManager.transcriptionEngine == .whisperKit {
                                    pendingWhisperModel = newModel
                                    showModelDownloadConfirm = true
                                }
                            }
                            .disabled(whisperManager.isModelLoading)
                        }
                        
                        // Show loading indicator when model is loading
                        if whisperManager.isModelLoading {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(String(format: NSLocalizedString("Downloading %@...", comment: "Model downloading status"), themeManager.whisperModel.displayName))
                                    .font(.caption)
                                    .foregroundColor(.secondaryText)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .modifier(SettingsRowCard())
                    
                    HStack {
                        Label(NSLocalizedString("Language", comment: "Language setting label"), systemImage: "globe")
                        Spacer()
                        Picker("", selection: $themeManager.transcriptionLanguage) {
                            ForEach(TranscriptionLanguage.allCases, id: \.rawValue) { language in
                                Text(language.displayName)
                                    .tag(language)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .onChange(of: themeManager.transcriptionLanguage) { _, newLanguage in
                            themeManager.updateTranscriptionLanguage(newLanguage)
                        }
                    }
                    .modifier(SettingsRowCard())
                    
                    if TranslationManager.isAvailable {
                        Toggle(isOn: $themeManager.enableTranslation) {
                            Label(NSLocalizedString("Enable Translation", comment: "Enable translation toggle label"), systemImage: "translate")
                        }
                        .onChange(of: themeManager.enableTranslation) { _, newValue in
                            themeManager.updateEnableTranslation(newValue)
                        }
                        .modifier(SettingsRowCard())
                        
                        if themeManager.enableTranslation {
                            HStack {
                                Label(NSLocalizedString("Translate To", comment: "Translation target language label"), systemImage: "arrow.right.circle")
                                Spacer()
                                Picker("", selection: $themeManager.translationTargetLanguage) {
                                    ForEach(TranscriptionLanguage.allCases, id: \.rawValue) { language in
                                        Text(language.displayName)
                                            .tag(language)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .onChange(of: themeManager.translationTargetLanguage) { _, newLanguage in
                                    themeManager.updateTranslationTargetLanguage(newLanguage)
                                }
                            }
                            .modifier(SettingsRowCard())
                        }
                    } else {
                        HStack {
                            Label(NSLocalizedString("Translation", comment: "Translation feature label"), systemImage: "translate")
                            Spacer()
                            Text(NSLocalizedString("Requires iOS 17.4+", comment: "iOS version requirement text"))
                                .font(.caption)
                                .foregroundColor(.secondaryText)
                        }
                        .modifier(SettingsRowCard())
                    }
                }
                
                // Goals Section
                Section(NSLocalizedString("Reading Goals", comment: "Settings section: Reading Goals")) {
                    Button {
                        tempGoal = statistics.monthlyGoal / 3600
                        showingGoalEditor = true
                    } label: {
                        HStack {
                            Label(NSLocalizedString("Monthly Goal", comment: "Monthly goal setting label"), systemImage: "target")
                            Spacer()
                            Text(statistics.formattedMonthlyGoal)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                }
                
                // Statistics Section
                Section(NSLocalizedString("Statistics", comment: "Settings section: Statistics")) {
                    StatisticRowView(
                        icon: "clock",
                        title: NSLocalizedString("Total Listening Time", comment: "Total listening time statistic"),
                        value: statistics.formattedTotalTime
                    )
                    
                    StatisticRowView(
                        icon: "books.vertical",
                        title: NSLocalizedString("Books Completed", comment: "Books completed statistic"),
                        value: "\(statistics.booksCompleted)"
                    )
                    
                    StatisticRowView(
                        icon: "speedometer",
                        title: NSLocalizedString("Average Speed", comment: "Average playback speed statistic"),
                        value: String(format: "%.1fx", statistics.averageSpeed)
                    )
                    
                    StatisticRowView(
                        icon: "flame",
                        title: NSLocalizedString("Current Streak", comment: "Current reading streak statistic"),
                        value: "\(statistics.currentStreak) \(NSLocalizedString("days", comment: "Days unit"))"
                    )
                    
                    StatisticRowView(
                        icon: "trophy",
                        title: NSLocalizedString("Longest Streak", comment: "Longest reading streak statistic"),
                        value: "\(statistics.longestStreak) \(NSLocalizedString("days", comment: "Days unit"))"
                    )
                }

                // Data Management
                Section(NSLocalizedString("Data", comment: "Settings section: Data management")) {
                    Button(role: .destructive) {
                        showResetStatsConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text(NSLocalizedString("Reset Listening Stats", comment: "Reset stats button label"))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .modifier(SettingsRowCard())
                }
                
                // About Section
                Section(NSLocalizedString("About", comment: "Settings section: About")) {
                    HStack {
                        Label(NSLocalizedString("Version", comment: "App version label"), systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://github.com")!) {
                        Label(NSLocalizedString("GitHub", comment: "GitHub link label"), systemImage: "link")
                    }
                }
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

private struct SettingsRowCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(Color.cardBackground)
            .cornerRadius(14)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }
}

struct StatisticRowView: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

struct StatisticsView: View {
    @ObservedObject var statistics: ReadingStatistics
    @StateObject private var themeManager = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 24) {
                    VStack(spacing: 16) {
                        VStack(spacing: 8) {
                            Text(NSLocalizedString("This Month", comment: "This month progress header"))
                                .font(.headline)
                                .foregroundColor(.primaryText)
                            
                            Text(statistics.formattedMonthlyProgress)
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundColor(.accentColor)
                            
                            Text(String(format: NSLocalizedString("of %@ goal", comment: "Monthly goal progress text"), statistics.formattedMonthlyGoal))
                                .font(.subheadline)
                                .foregroundColor(.secondaryText)
                        }
                        
                        // Progress Ring
                        ZStack {
                            Circle()
                                .stroke(Color.secondaryBackground, lineWidth: 12)
                            
                            Circle()
                                .trim(from: 0, to: statistics.monthlyGoalProgress)
                                .stroke(
                                    LinearGradient(
                                        colors: [.accentColor, .accentColor.opacity(0.6)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut(duration: 1), value: statistics.monthlyGoalProgress)
                            
                            Text("\(Int(statistics.monthlyGoalProgress * 100))%")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.primaryText)
                        }
                        .frame(width: 150, height: 150)
                    }
                    .padding(24)
                    .background(Color.cardBackground)
                    .cornerRadius(20)
                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                    
                    // Statistics Grid
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        StatCardView(
                            title: NSLocalizedString("Total Time", comment: "Total time stat card title"),
                            value: statistics.formattedTotalTime,
                            icon: "clock",
                            color: .blue
                        )
                        
                        StatCardView(
                            title: NSLocalizedString("Books Completed", comment: "Books completed stat card title"),
                            value: "\(statistics.booksCompleted)",
                            icon: "books.vertical",
                            color: .green
                        )
                        
                        StatCardView(
                            title: NSLocalizedString("Average Speed", comment: "Average speed stat card title"),
                            value: String(format: "%.1fx", statistics.averageSpeed),
                            icon: "speedometer",
                            color: .orange
                        )
                        
                        StatCardView(
                            title: NSLocalizedString("Current Streak", comment: "Current streak stat card title"),
                            value: "\(statistics.currentStreak)",
                            subtitle: NSLocalizedString("days", comment: "Days unit for stat card"),
                            icon: "flame",
                            color: .red
                        )
                    }
                    
                    // Achievement Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text(NSLocalizedString("Achievements", comment: "Achievements section header"))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primaryText)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            AchievementView(
                                icon: "trophy.fill",
                                title: NSLocalizedString("Longest Streak", comment: "Longest streak achievement title"),
                                value: "\(statistics.longestStreak) \(NSLocalizedString("days", comment: "Days unit"))",
                                isUnlocked: statistics.longestStreak >= 7
                            )
                            
                            AchievementView(
                                icon: "book.fill",
                                title: NSLocalizedString("First Book", comment: "First book achievement title"),
                                value: NSLocalizedString("Complete", comment: "Achievement completion status"),
                                isUnlocked: statistics.booksCompleted >= 1
                            )
                            
                            AchievementView(
                                icon: "clock.fill",
                                title: NSLocalizedString("10 Hours", comment: "10 hours achievement title"),
                                value: statistics.totalListeningTime >= 36000 ? NSLocalizedString("Complete", comment: "Achievement completion status") : NSLocalizedString("In Progress", comment: "Achievement in progress status"),
                                isUnlocked: statistics.totalListeningTime >= 36000
                            )
                        }
                    }
                }
                .padding()
            }
            .background(Color.primaryBackground.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("Statistics", comment: "Statistics view title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Done", comment: "Done button")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        .tint(themeManager.accentColor.color)
    }
}

struct StatCardView: View {
    let title: String
    let value: String
    var subtitle: String = ""
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text(value)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primaryText)
                    
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondaryText)
                    }
                }
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondaryText)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

struct AchievementView: View {
    let icon: String
    let title: String
    let value: String
    let isUnlocked: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(isUnlocked ? .yellow : .secondaryText)
            
            Text(title)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.primaryText)
                .multilineTextAlignment(.center)
            
            Text(value)
                .font(.caption2)
                .foregroundColor(.secondaryText)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(Color.cardBackground)
        .cornerRadius(12)
        .opacity(isUnlocked ? 1.0 : 0.6)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

#Preview("Settings") {
    SettingsView()
}

#Preview("Statistics") {
    StatisticsView(statistics: ReadingStatistics())
}
