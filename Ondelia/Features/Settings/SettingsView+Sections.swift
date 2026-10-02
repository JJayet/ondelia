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
                Menu {
                    Picker(
                        NSLocalizedString("Accent Color", comment: "Accent color setting label"),
                        selection: Binding(
                            get: { themeManager.accentColor },
                            set: { themeManager.setAccentColor($0) }
                        )
                    ) {
                        ForEach(AccentColor.allCases, id: \.rawValue) { color in
                            Label {
                                Text(color.displayName)
                            } icon: {
                                Image(size: CGSize(width: 18, height: 18)) { context in
                                    context.fill(
                                        Path(ellipseIn: CGRect(x: 0, y: 0, width: 18, height: 18)),
                                        with: .color(color.color)
                                    )
                                }
                                .renderingMode(.original)
                            }
                            .tag(color)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(themeManager.accentColor.color)
                            .frame(width: 18, height: 18)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(NSLocalizedString("Accent Color", comment: "Accent color setting label"))
                .accessibilityValue(themeManager.accentColor.displayName)
            }

            // iOS remembers the alternate icon itself, so the picker reads it back rather than
            // storing a copy. An iPad app on the Mac cannot swap its icon at all, so no row there.
            if UIApplication.shared.supportsAlternateIcons {
                SettingsDivider()

                SettingsRow(title: NSLocalizedString("App Icon", comment: "App icon setting label")) {
                    Picker(selection: $appIcon) {
                        Text(NSLocalizedString("Day", comment: "Light app icon")).tag("Day")
                        Text(NSLocalizedString("Night", comment: "Dark app icon")).tag("Night")
                    } label: { Text(verbatim: "") }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .onChange(of: appIcon) { _, icon in
                        UIApplication.shared.setAlternateIconName(icon == "Day" ? nil : icon)
                    }
                }
            }

            SettingsDivider()

            SettingsRow(title: NSLocalizedString("Grid density", comment: "Grid density menu title")) {
                Picker(selection: $gridColumns) {
                    ForEach(LibraryView.gridDensityChoices, id: \.self) { count in
                        Text(LibraryView.gridDensityName(count)).tag(count)
                    }
                } label: { Text(verbatim: "") }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    var librarySection: some View {
        SettingsSection(title: NSLocalizedString("Library", comment: "Library navigation title")) {
            // On by default: a Hardcover series becomes a collection as soon as a volume is linked.
            // Off, the library asks once per series instead.
            SettingsRow(title: NSLocalizedString("Group series into collections", comment: "Automatic series collections toggle")) {
                Toggle("", isOn: $autoSeriesCollections)
                    .labelsHidden()
                    .onChange(of: autoSeriesCollections) { _, _ in AudiobookManager.shared.reconcileSeriesCollections() }
            }

            SettingsDivider()

            SettingsRow(title: NSLocalizedString("Show series books you don't own", comment: "Toggle for catalogue volumes in series cards")) {
                Toggle("", isOn: $showMissingSeriesBooks)
                    .labelsHidden()
            }
        }
    }

    var playbackSection: some View {
        SettingsSection(title: NSLocalizedString("Playback", comment: "Settings section: Playback")) {
            skipIntervalRow(
                title: NSLocalizedString("Skip Backward", comment: "Skip backward accessibility label"),
                selection: Binding(
                    get: { themeManager.skipBackInterval },
                    set: { themeManager.setSkipBackInterval($0) }
                )
            )

            SettingsDivider()

            skipIntervalRow(
                title: NSLocalizedString("Skip Forward", comment: "Skip forward accessibility label"),
                selection: Binding(
                    get: { themeManager.skipForwardInterval },
                    set: { themeManager.setSkipForwardInterval($0) }
                )
            )

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

            // Off by default. On, every play starts the last timer the listener chose.
            SettingsRow(title: NSLocalizedString("Auto Sleep Timer", comment: "Start the last used sleep timer on every play")) {
                Toggle("", isOn: $autoSleepTimer)
                    .labelsHidden()
            }

            SettingsDivider()

            // Off by default: the file, its progress and its bookmarks go the moment the book ends.
            SettingsRow(title: NSLocalizedString("Delete book when finished", comment: "Delete on completion toggle")) {
                Toggle("", isOn: $deleteOnCompletion)
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

    private func skipIntervalRow(title: String, selection: Binding<SkipInterval>) -> some View {
        SettingsRow(title: title) {
            Picker("", selection: selection) {
                ForEach(SkipInterval.allCases, id: \.rawValue) { interval in
                    Text(interval.displayName).tag(interval)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    var goalsSection: some View {
        SettingsSection(title: NSLocalizedString("Reading Goals", comment: "Settings section: Reading Goals")) {
            Button {
                withHapticFeedback {
                    tempGoal = statistics.monthlyGoal / 3600
                    showingGoalEditor = true
                }
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
            .simultaneousGesture(TapGesture().onEnded { withHapticFeedback {} })

            SettingsDivider()

            NavigationLink {
                AudiobookShelfSettingsView()
            } label: {
                SettingsRow(title: "AudiobookShelf", icon: "server.rack") {
                    SettingsValue(text: AudiobookShelfService.shared.isSignedIn
                        ? NSLocalizedString("Connected", comment: "AudiobookShelf status: signed in")
                        : NSLocalizedString("Not connected", comment: "AudiobookShelf status: signed out"))
                }
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { withHapticFeedback {} })
        }
    }

    var dataSection: some View {
        SettingsSection(title: NSLocalizedString("Data", comment: "Settings section: Data management")) {
            SettingsRow(title: NSLocalizedString("iCloud Sync", comment: "iCloud sync toggle")) {
                Toggle("", isOn: $iCloudSync)
                    .labelsHidden()
            }
            Text(NSLocalizedString(
                "Progress, bookmarks and book details sync through iCloud. Audio stays on each device. Takes effect the next time the app starts.",
                comment: "iCloud sync explanation"
            ))
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
            .padding(.top, -8)

            SettingsDivider()

            Button {
                withHapticFeedback { showingStorage = true }
            } label: {
                SettingsRow(title: NSLocalizedString("Storage", comment: "Storage view title")) {
                    SettingsValue(text: storageBytes?.formatted(.byteCount(style: .file)) ?? "")
                }
            }
            .buttonStyle(.plain)

            SettingsDivider()

            Button {
                withHapticFeedback { showingBackupRestore = true }
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
                withHapticFeedback { showResetStatsConfirm = true }
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

            Button { withHapticFeedback { onboardingCompleted = false } } label: {
                SettingsRow(title: NSLocalizedString("Show Welcome Screen", comment: "Settings: replay the onboarding"))
            }
            .buttonStyle(.plain)

            SettingsDivider()

            Button { withHapticFeedback { tipsResetPending = true } } label: {
                SettingsRow(title: NSLocalizedString("Reset Tips", comment: "Settings: show every in-app tip again")) {
                    if tipsResetPending {
                        Text(NSLocalizedString("On next launch", comment: "Settings: tips reset is pending"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(tipsResetPending)
        }
    }
}
