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
    /// Half the headline's cap height: the middle of a wrapped title's first line.
    @ScaledMetric(relativeTo: .headline) private var halfCapHeight: CGFloat = 6

    var body: some View {
        HStack(alignment: .optionTitle, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 30, height: 28)
                .alignmentGuide(.optionTitle) { $0[VerticalAlignment.center] }

            VStack(alignment: .leading, spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        Text(title).font(.headline).fixedSize()
                            .alignmentGuide(.optionTitle) { $0[VerticalAlignment.center] }
                        Spacer(minLength: 0)
                        optionControl
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                            // A wrapped title keeps the symbol on its first line.
                            .alignmentGuide(.optionTitle) { $0[.firstTextBaseline] - halfCapHeight }
                        optionControl
                    }
                }
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
    }

    private var optionControl: some View {
        control
            .fixedSize()
            .accessibilityLabel(Text(title))
    }
}

struct OnboardingLookPage: View {
    @Bindable private var themeManager = ThemeManager.shared
    // iOS remembers the alternate icon itself, so the picker reads it back rather than storing a copy.
    @State private var appIcon = UIApplication.shared.alternateIconName ?? "Day"

    var body: some View {
        VStack(spacing: 28) {
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
                    AccentColorMenu()
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
        }
    }
}

struct OnboardingPlaybackPage: View {
    @Bindable private var themeManager = ThemeManager.shared
    @AppStorage(GlobalAudioManager.autoSleepTimerKey) private var autoSleepTimer = false
    @AppStorage(GlobalAudioManager.deleteOnCompletionKey) private var deleteOnCompletion = false

    var body: some View {
        VStack(spacing: 28) {
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

private extension VerticalAlignment {
    /// The symbol sits level with the title, however tall the control beside the title is.
    enum OptionTitle: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context[.top] }
    }

    static let optionTitle = VerticalAlignment(OptionTitle.self)
}
