import SwiftUI

// MARK: - List sections (transcription lives in SettingsView+TranscriptionSection.swift)
extension SettingsView {
    var appearanceSection: some View {
        Section(NSLocalizedString("Appearance", comment: "Settings section: Appearance")) {
            HStack {
                Label(NSLocalizedString("Theme", comment: "Theme setting label"), systemImage: "paintbrush")
                    .foregroundStyle(Color.primaryText)
                Spacer()
                Picker("", selection: $themeManager.currentTheme) {
                    ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                        Text(theme.displayName)
                            .foregroundStyle(Color.primaryText)
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
                    .foregroundStyle(themeManager.accentColor.color)
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
                    .foregroundStyle(Color.primaryText)
                Spacer()
                Picker(NSLocalizedString("Skip Interval", comment: "Skip interval picker label"), selection: $themeManager.skipInterval) {
                    ForEach(SkipInterval.allCases, id: \.rawValue) { interval in
                        Text(interval.displayName)
                            .foregroundStyle(Color.primaryText)
                            .tag(interval)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .onChange(of: themeManager.skipInterval) { _, newInterval in
                    themeManager.setSkipInterval(newInterval)
                }
            }
            .modifier(SettingsRowCard())

            // Off by default: a speed picked for one narrator rarely suits the next one.
            Toggle(isOn: Binding(
                get: { themeManager.globalSpeedEnabled },
                set: { themeManager.setGlobalSpeedEnabled($0) }
            )) {
                Label(
                    NSLocalizedString("Same Speed For All Books", comment: "Global playback speed toggle"),
                    systemImage: "speedometer"
                )
                .foregroundStyle(Color.primaryText)
            }
            .modifier(SettingsRowCard())

            if themeManager.globalSpeedEnabled {
                HStack {
                    Label("", systemImage: "gauge.with.dots.needle.50percent")
                        .foregroundStyle(Color.primaryText)
                    Spacer()
                    Picker(
                        NSLocalizedString("Speed", comment: "Playback speed picker label"),
                        selection: Binding(
                            get: { themeManager.globalSpeed },
                            set: { themeManager.setGlobalSpeed($0) }
                        )
                    ) {
                        ForEach(PlaybackSpeed.choices, id: \.self) { speed in
                            Text(PlaybackSpeed.displayName(speed))
                                .foregroundStyle(Color.primaryText)
                                .tag(speed)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                .modifier(SettingsRowCard())
            }
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
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
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
                    .foregroundStyle(.secondary)
            }

            Link(destination: URL(string: "https://github.com")!) {
                Label(NSLocalizedString("GitHub", comment: "GitHub link label"), systemImage: "link")
            }
        }
    }
}
