import SwiftUI

// MARK: - List sections (transcription lives in SettingsView+TranscriptionSection.swift)
extension SettingsView {
    var appearanceSection: some View {
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
    }

    var playbackSection: some View {
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
    }

    var goalsSection: some View {
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
    }

    var statisticsSection: some View {
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
    }

    var dataSection: some View {
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
    }

    var aboutSection: some View {
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
}
