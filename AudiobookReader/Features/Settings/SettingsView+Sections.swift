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
                .pickerStyle(.menu)
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
                .pickerStyle(.menu)
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
                Label(NSLocalizedString("Skip Interval", comment: "Skip interval picker label"), systemImage: "goforward")
                    .foregroundStyle(Color.primaryText)
                Spacer()
                Picker("", selection: $themeManager.skipInterval) {
                    ForEach(SkipInterval.allCases, id: \.rawValue) { interval in
                        Text(interval.displayName)
                            .foregroundStyle(Color.primaryText)
                            .tag(interval)
                    }
                }
                .pickerStyle(.menu)
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
                    Label(NSLocalizedString("Speed", comment: "Playback speed picker label"), systemImage: "gauge.with.dots.needle.50percent")
                        .foregroundStyle(Color.primaryText)
                    Spacer()
                    Picker(
                        "",
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
                    .pickerStyle(.menu)
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

    var dataSection: some View {
        Section(NSLocalizedString("Data", comment: "Settings section: Data management")) {
            Button {
                showingBackupRestore = true
            } label: {
                Label(
                    NSLocalizedString("Restore Backup", comment: "Restore backup button label"),
                    systemImage: "clock.arrow.circlepath"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .modifier(SettingsRowCard())

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

    var integrationsSection: some View {
        Section(NSLocalizedString("Integrations", comment: "Settings section: Integrations")) {
            NavigationLink {
                HardcoverSettingsView()
            } label: {
                HStack {
                    Label("Hardcover", systemImage: "books.vertical")
                        .foregroundStyle(Color.primaryText)
                    Spacer()
                    if HardcoverService.shared.isLinked {
                        Text(NSLocalizedString("On", comment: "Integration enabled"))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .modifier(SettingsRowCard())
        }
    }

    var aboutSection: some View {
        Section(NSLocalizedString("About", comment: "Settings section: About")) {
            HStack {
                Label(NSLocalizedString("Version", comment: "App version label"), systemImage: "info.circle")
                Spacer()
                Text(Bundle.main.shortVersionString)
                    .foregroundStyle(.secondary)
            }

            Link(destination: URL(string: "https://github.com/jjayet/AudiobookReader")!) {
                Label(NSLocalizedString("GitHub", comment: "GitHub link label"), systemImage: "link")
            }
        }
    }
}
