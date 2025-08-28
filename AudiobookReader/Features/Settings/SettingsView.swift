import SwiftUI

struct SettingsView: View {
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var statistics = ReadingStatistics()
    @StateObject private var whisperManager = WhisperTranscriptionManager.shared
    @Environment(\.presentationMode) var presentationMode
    @State private var showingGoalEditor = false
    @State private var tempGoal: Double = 0
    
    var body: some View {
        NavigationView {
            List {
                // Appearance Section
                Section("Appearance") {
                    HStack {
                        Label("Theme", systemImage: "paintbrush")
                        Spacer()
                        Picker("Theme", selection: $themeManager.currentTheme) {
                            ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                                Text(theme.displayName)
                                    .tag(theme)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .onChange(of: themeManager.currentTheme) { _, newTheme in
                            themeManager.updateTheme(newTheme)
                        }
                    }
                    
                    HStack {
                        Label("Accent Color", systemImage: "circle.fill")
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
                            themeManager.updateAccentColor(newColor)
                        }
                    }
                }
                
                // Playback Section
                Section("Playback") {
                    HStack {
                        Label("Skip Interval", systemImage: "goforward")
                        Spacer()
                        Picker("Skip Interval", selection: $themeManager.skipInterval) {
                            ForEach(SkipInterval.allCases, id: \.rawValue) { interval in
                                Text(interval.displayName)
                                    .tag(interval)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .onChange(of: themeManager.skipInterval) { _, newInterval in
                            themeManager.updateSkipInterval(newInterval)
                        }
                    }
                }
                
                // Transcription Section
                Section("Transcription") {
                    VStack(alignment: .leading) {
                        HStack {
                            Label("WhisperKit Model", systemImage: "brain")
                            Spacer()
                            Picker("Model", selection: $themeManager.whisperModel) {
                                ForEach(WhisperModel.allCases, id: \.rawValue) { model in
                                    VStack(alignment: .leading) {
                                        Text(model.displayName)
                                            .font(.body)
                                        HStack {
                                            Text(model.sizeDescription)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text("•")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            HStack(spacing: 2) {
                                                ForEach(0..<5) { index in
                                                    Image(systemName: index < model.accuracyRating ? "star.fill" : "star")
                                                        .font(.system(size: 8))
                                                        .foregroundColor(index < model.accuracyRating ? .yellow : .secondary)
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
                            }
                            .disabled(whisperManager.isModelLoading)
                        }
                        
                        // Show loading indicator when model is loading
                        if whisperManager.isModelLoading {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Downloading \(themeManager.whisperModel.displayName)...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        }
                    }
                    
                    HStack {
                        Label("Language", systemImage: "globe")
                        Spacer()
                        Picker("Language", selection: $themeManager.transcriptionLanguage) {
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
                    
                    if TranslationManager.isAvailable {
                        Toggle(isOn: $themeManager.enableTranslation) {
                            Label("Enable Translation", systemImage: "translate")
                        }
                        .onChange(of: themeManager.enableTranslation) { _, newValue in
                            themeManager.updateEnableTranslation(newValue)
                        }
                        
                        if themeManager.enableTranslation {
                            HStack {
                                Label("Translate To", systemImage: "arrow.right.circle")
                                Spacer()
                                Picker("Target Language", selection: $themeManager.translationTargetLanguage) {
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
                        }
                    } else {
                        HStack {
                            Label("Translation", systemImage: "translate")
                            Spacer()
                            Text("Requires iOS 17.4+")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Goals Section
                Section("Reading Goals") {
                    Button {
                        tempGoal = statistics.monthlyGoal / 3600
                        showingGoalEditor = true
                    } label: {
                        HStack {
                            Label("Monthly Goal", systemImage: "target")
                            Spacer()
                            Text(statistics.formattedMonthlyGoal)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                }
                
                // Statistics Section
                Section("Statistics") {
                    StatisticRowView(
                        icon: "clock",
                        title: "Total Listening Time",
                        value: statistics.formattedTotalTime
                    )
                    
                    StatisticRowView(
                        icon: "books.vertical",
                        title: "Books Completed",
                        value: "\(statistics.booksCompleted)"
                    )
                    
                    StatisticRowView(
                        icon: "speedometer",
                        title: "Average Speed",
                        value: String(format: "%.1fx", statistics.averageSpeed)
                    )
                    
                    StatisticRowView(
                        icon: "flame",
                        title: "Current Streak",
                        value: "\(statistics.currentStreak) days"
                    )
                    
                    StatisticRowView(
                        icon: "trophy",
                        title: "Longest Streak",
                        value: "\(statistics.longestStreak) days"
                    )
                }
                
                // About Section
                Section("About") {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://github.com")!) {
                        Label("GitHub", systemImage: "link")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Monthly Goal", isPresented: $showingGoalEditor) {
                TextField("Hours", value: $tempGoal, format: .number)
                    .keyboardType(.decimalPad)
                
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    statistics.updateMonthlyGoal(tempGoal * 3600) // Convert hours to seconds
                }
            } message: {
                Text("Set your monthly listening goal in hours")
            }
        }
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        .accentColor(themeManager.accentColor.color)
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
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 24) {
                    // Monthly Progress Card
                    VStack(spacing: 16) {
                        VStack(spacing: 8) {
                            Text("This Month")
                                .font(.headline)
                                .foregroundColor(.primaryText)
                            
                            Text(statistics.formattedMonthlyProgress)
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundColor(.accentColor)
                            
                            Text("of \(statistics.formattedMonthlyGoal) goal")
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
                            title: "Total Time",
                            value: statistics.formattedTotalTime,
                            icon: "clock",
                            color: .blue
                        )
                        
                        StatCardView(
                            title: "Books Completed",
                            value: "\(statistics.booksCompleted)",
                            icon: "books.vertical",
                            color: .green
                        )
                        
                        StatCardView(
                            title: "Average Speed",
                            value: String(format: "%.1fx", statistics.averageSpeed),
                            icon: "speedometer",
                            color: .orange
                        )
                        
                        StatCardView(
                            title: "Current Streak",
                            value: "\(statistics.currentStreak)",
                            subtitle: "days",
                            icon: "flame",
                            color: .red
                        )
                    }
                    
                    // Achievement Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Achievements")
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
                                title: "Longest Streak",
                                value: "\(statistics.longestStreak) days",
                                isUnlocked: statistics.longestStreak >= 7
                            )
                            
                            AchievementView(
                                icon: "book.fill",
                                title: "First Book",
                                value: "Complete",
                                isUnlocked: statistics.booksCompleted >= 1
                            )
                            
                            AchievementView(
                                icon: "clock.fill",
                                title: "10 Hours",
                                value: statistics.totalListeningTime >= 36000 ? "Complete" : "In Progress",
                                isUnlocked: statistics.totalListeningTime >= 36000
                            )
                        }
                    }
                }
                .padding()
            }
            .background(Color.primaryBackground.ignoresSafeArea())
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        .accentColor(themeManager.accentColor.color)
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
                .foregroundColor(isUnlocked ? .yellow : .secondary)
            
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

#Preview {
    SettingsView()
}
