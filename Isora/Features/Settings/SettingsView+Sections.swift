import SwiftUI

// MARK: - Settings sections
//
// Each section is one glass card of hairline-separated rows. Pickers keep the `.menu` style:
// its value reads as the design's tinted "Système ⌄" on the right of the row.
extension SettingsView {
    var appearanceSection: some View {
        SettingsSection(title: NSLocalizedString("Appearance", comment: "Settings section: Appearance")) {
            SettingsRow(title: NSLocalizedString("Theme", comment: "Theme setting label")) {
                Picker(selection: $themeManager.currentTheme) {
                    ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                } label: { Text(verbatim: "") }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: themeManager.currentTheme) { _, newTheme in
                    themeManager.setTheme(newTheme)
                }
            }

            SettingsDivider()

            SettingsRow(title: NSLocalizedString("Accent Color", comment: "Accent color setting label")) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(themeManager.accentColor.color)
                        .frame(width: 18, height: 18)
                    Picker(selection: $themeManager.accentColor) {
                        ForEach(AccentColor.allCases, id: \.rawValue) { color in
                            Text(color.displayName).tag(color)
                        }
                    } label: { Text(verbatim: "") }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .onChange(of: themeManager.accentColor) { _, newColor in
                        themeManager.setAccentColor(newColor)
                    }
                }
            }
        }
    }

    var playbackSection: some View {
        SettingsSection(title: NSLocalizedString("Playback", comment: "Settings section: Playback")) {
            SettingsRow(title: NSLocalizedString("Skip Interval", comment: "Skip interval picker label")) {
                Picker(selection: $themeManager.skipInterval) {
                    ForEach(SkipInterval.allCases, id: \.rawValue) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                } label: { Text(verbatim: "") }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: themeManager.skipInterval) { _, newInterval in
                    themeManager.setSkipInterval(newInterval)
                }
            }

            SettingsDivider()

            SettingsRow(title: NSLocalizedString("Book opening delay", comment: "Full player playback delay setting")) {
                Picker("Book opening delay", selection: $bookOpeningDelayMS) {
                    Text("Off").tag(0)
                    Text(verbatim: "100 ms").tag(100)
                    Text(verbatim: "200 ms").tag(200)
                    Text(verbatim: "500 ms").tag(500)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityHint(Text("Delay playback when opening the full player. Miniplayer controls start immediately."))
            }

            SettingsDivider()

            // On by default: resuming mid-word is the thing everyone notices, and the rewind
            // after a short pause is small enough to go unremarked.
            SettingsRow(title: NSLocalizedString("Smart Rewind", comment: "Smart rewind toggle")) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { themeManager.smartRewindEnabled },
                        set: { themeManager.setSmartRewindEnabled($0) }
                    )
                )
                .labelsHidden()
            }

            SettingsDivider()

            SettingsRow(title: NSLocalizedString("Chapter Times", comment: "Player chapter time line toggle")) {
                Toggle("", isOn: $showChapterTimes)
                    .labelsHidden()
            }

            SettingsDivider()

            // Off by default: a speed picked for one narrator rarely suits the next one.
            SettingsRow(title: NSLocalizedString("Same Speed For All Books", comment: "Global playback speed toggle")) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { themeManager.globalSpeedEnabled },
                        set: { themeManager.setGlobalSpeedEnabled($0) }
                    )
                )
                .labelsHidden()
            }

            if themeManager.globalSpeedEnabled {
                SettingsDivider()

                SettingsRow(title: NSLocalizedString("Speed", comment: "Playback speed picker label")) {
                    Picker(
                        "",
                        selection: Binding(
                            get: { themeManager.globalSpeed },
                            set: { themeManager.setGlobalSpeed($0) }
                        )
                    ) {
                        ForEach(PlaybackSpeed.choices, id: \.self) { speed in
                            Text(PlaybackSpeed.displayName(speed)).tag(speed)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
        }
    }

    var goalsSection: some View {
        SettingsSection(title: NSLocalizedString("Reading Goals", comment: "Settings section: Reading Goals")) {
            Button {
                tempGoal = statistics.monthlyGoal / 3600
                showingGoalEditor = true
            } label: {
                SettingsRow(title: NSLocalizedString("Monthly Goal", comment: "Monthly goal setting label")) {
                    SettingsValue(text: statistics.formattedMonthlyGoal)
                }
            }
            .buttonStyle(.plain)
        }
    }

    var integrationsSection: some View {
        SettingsSection(title: NSLocalizedString("Integrations", comment: "Settings section: Integrations")) {
            NavigationLink {
                HardcoverSettingsView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 28, height: 28)
                        .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Hardcover").font(.system(size: 15))
                        HardcoverStatusLine()
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 15)
            }
            .buttonStyle(.plain)
        }
    }

    var dataSection: some View {
        SettingsSection(title: NSLocalizedString("Data", comment: "Settings section: Data management")) {
            Button {
                showingBackupRestore = true
            } label: {
                SettingsRow(title: NSLocalizedString("Restore Backup", comment: "Restore backup button label")) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            SettingsDivider()

            Button {
                showResetStatsConfirm = true
            } label: {
                SettingsRow(
                    title: NSLocalizedString("Reset Listening Stats", comment: "Reset stats button label"),
                    titleColor: .red
                )
            }
            .buttonStyle(.plain)
        }
    }

    var aboutSection: some View {
        SettingsSection(title: NSLocalizedString("About", comment: "Settings section: About")) {
            SettingsRow(title: NSLocalizedString("Version", comment: "App version label")) {
                Text(Bundle.main.shortVersionString)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }

            SettingsDivider()

            Link(destination: URL(string: "https://github.com/JJayet/audiobook")!) {
                SettingsRow(title: NSLocalizedString("GitHub", comment: "GitHub link label")) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }
}
