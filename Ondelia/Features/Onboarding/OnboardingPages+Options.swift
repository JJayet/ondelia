import SwiftUI

// MARK: - Option pages
//
// The settings worth choosing before the first listen, each with the line Settings never had
// room for. Every control writes straight to the same store Settings reads.

/// A feature row with its control on the right, the shape of every option on these pages.
struct OnboardingOptionRow<Control: View>: View {
    let systemImage: String
    let title: String
    let detail: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 12) {
            OnboardingFeatureRow(systemImage: systemImage, title: title, detail: detail)
            control
        }
        .padding(16)
    }
}

struct OnboardingLookPage: View {
    @Bindable private var themeManager = ThemeManager.shared
    // iOS remembers the alternate icon itself, so the picker reads it back rather than storing a copy.
    @State private var appIcon = UIApplication.shared.alternateIconName ?? "Day"

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            OnboardingHeader(
                systemImage: "paintpalette.fill",
                title: NSLocalizedString("Make it yours", comment: "Onboarding: appearance title"),
                text: NSLocalizedString("How the app looks. All of it can change later in Settings.", comment: "Onboarding: appearance body")
            )

            VStack(spacing: 0) {
                OnboardingOptionRow(
                    systemImage: "circle.lefthalf.filled",
                    title: NSLocalizedString("Theme", comment: "Theme setting label"),
                    detail: NSLocalizedString("Light, dark, or whatever the system is using.", comment: "Onboarding: theme detail")
                ) {
                    Picker("", selection: $themeManager.currentTheme) {
                        ForEach(AppTheme.allCases, id: \.rawValue) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .onChange(of: themeManager.currentTheme) { _, theme in themeManager.setTheme(theme) }
                }

                Divider().padding(.horizontal, 16)

                OnboardingOptionRow(
                    systemImage: "paintbrush.fill",
                    title: NSLocalizedString("Accent Color", comment: "Accent color setting label"),
                    detail: NSLocalizedString("Buttons, progress bars and highlights.", comment: "Onboarding: accent detail")
                ) {
                    Picker("", selection: $themeManager.accentColor) {
                        ForEach(AccentColor.allCases, id: \.rawValue) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .onChange(of: themeManager.accentColor) { _, color in themeManager.setAccentColor(color) }
                }

                Divider().padding(.horizontal, 16)

                OnboardingOptionRow(
                    systemImage: "app.badge.fill",
                    title: NSLocalizedString("App Icon", comment: "App icon setting label"),
                    detail: NSLocalizedString("A light or a dark icon on the Home Screen.", comment: "Onboarding: app icon detail")
                ) {
                    Picker("", selection: $appIcon) {
                        Text(NSLocalizedString("Day", comment: "Light app icon")).tag("Day")
                        Text(NSLocalizedString("Night", comment: "Dark app icon")).tag("Night")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .onChange(of: appIcon) { _, icon in
                        UIApplication.shared.setAlternateIconName(icon == "Day" ? nil : icon)
                    }
                }
            }
            .glassCard(cornerRadius: 22)
            .padding(.horizontal, 24)
            Spacer()
            Spacer()
        }
    }
}

struct OnboardingPlaybackPage: View {
    @Bindable private var themeManager = ThemeManager.shared
    @AppStorage(GlobalAudioManager.autoSleepTimerKey) private var autoSleepTimer = false
    @AppStorage(GlobalAudioManager.deleteOnCompletionKey) private var deleteOnCompletion = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            OnboardingHeader(
                systemImage: "slider.horizontal.3",
                title: NSLocalizedString("How you listen", comment: "Onboarding: playback title"),
                text: NSLocalizedString("The defaults suit most people. Change what you already know you want.", comment: "Onboarding: playback body")
            )

            VStack(spacing: 0) {
                skipRow(
                    systemImage: "gobackward",
                    title: NSLocalizedString("Skip Backward", comment: "Skip backward accessibility label"),
                    detail: NSLocalizedString("How far the back button, and your headphones, jump.", comment: "Onboarding: skip back detail"),
                    selection: Binding(get: { themeManager.skipBackInterval }, set: { themeManager.setSkipBackInterval($0) })
                )

                Divider().padding(.horizontal, 16)

                skipRow(
                    systemImage: "goforward",
                    title: NSLocalizedString("Skip Forward", comment: "Skip forward accessibility label"),
                    detail: NSLocalizedString("How far the forward button jumps.", comment: "Onboarding: skip forward detail"),
                    selection: Binding(get: { themeManager.skipForwardInterval }, set: { themeManager.setSkipForwardInterval($0) })
                )

                Divider().padding(.horizontal, 16)

                OnboardingOptionRow(
                    systemImage: "arrow.uturn.backward.circle",
                    title: NSLocalizedString("Smart Rewind", comment: "Smart rewind toggle"),
                    detail: NSLocalizedString("Resuming steps back a little, more after a long pause, so you never land mid-sentence.", comment: "Onboarding: smart rewind detail")
                ) {
                    Toggle("", isOn: Binding(get: { themeManager.smartRewindEnabled }, set: { themeManager.setSmartRewindEnabled($0) }))
                        .labelsHidden()
                }

                Divider().padding(.horizontal, 16)

                OnboardingOptionRow(
                    systemImage: "moon.zzz.fill",
                    title: NSLocalizedString("Auto Sleep Timer", comment: "Start the last used sleep timer on every play"),
                    detail: NSLocalizedString("Every play starts the last sleep timer you chose.", comment: "Onboarding: auto sleep detail")
                ) {
                    Toggle("", isOn: $autoSleepTimer).labelsHidden()
                }

                Divider().padding(.horizontal, 16)

                OnboardingOptionRow(
                    systemImage: "trash.circle",
                    title: NSLocalizedString("Delete book when finished", comment: "Delete on completion toggle"),
                    detail: NSLocalizedString("Frees the storage the moment the last chapter ends. Progress and bookmarks go with it.", comment: "Onboarding: delete on completion detail")
                ) {
                    Toggle("", isOn: $deleteOnCompletion).labelsHidden()
                }
            }
            .glassCard(cornerRadius: 22)
            .padding(.horizontal, 24)
            Spacer()
            Spacer()
        }
    }

    private func skipRow(systemImage: String, title: String, detail: String, selection: Binding<SkipInterval>) -> some View {
        OnboardingOptionRow(systemImage: systemImage, title: title, detail: detail) {
            Picker("", selection: selection) {
                ForEach(SkipInterval.allCases, id: \.rawValue) { Text($0.displayName).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }
}

#Preview("Look") { OnboardingLookPage() }
#Preview("Playback") { OnboardingPlaybackPage() }
