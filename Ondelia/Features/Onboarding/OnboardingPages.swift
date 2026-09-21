import SwiftUI

struct OnboardingWelcomePage: View {
    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Ondelia"
    }

    var body: some View {
        VStack(spacing: 32) {
            OnboardingHeader(
                systemImage: "headphones.circle.fill",
                title: String(format: NSLocalizedString("Welcome to %@", comment: "Onboarding: welcome title, %@ is the app name"), appName),
                text: NSLocalizedString(
                    "Your audiobooks, played your way. Everything stays on your device unless you connect a service yourself.",
                    comment: "Onboarding: welcome body"
                )
            )
        }
    }
}

struct OnboardingImportPage: View {
    let importedCount: Int
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            OnboardingHeader(
                systemImage: "square.and.arrow.down.fill",
                title: NSLocalizedString("Bring your books", comment: "Onboarding: import title"),
                text: NSLocalizedString("Audio files, a folder of chapters, or a ZIP. Metadata, covers and chapters are read for you.", comment: "Onboarding: import body")
            )

            VStack(alignment: .leading, spacing: 16) {
                OnboardingFeatureRow(
                    systemImage: "folder",
                    title: NSLocalizedString("From Files or iCloud Drive", comment: "Onboarding: import source"),
                    detail: NSLocalizedString("Pick one book or many at once.", comment: "Onboarding: import source detail")
                )
                OnboardingFeatureRow(
                    systemImage: "square.and.arrow.up",
                    title: NSLocalizedString("From any app", comment: "Onboarding: share sheet import"),
                    detail: NSLocalizedString("Share a file to the app, or AirDrop it from a Mac.", comment: "Onboarding: share sheet detail")
                )
                OnboardingFeatureRow(
                    systemImage: "books.vertical",
                    title: NSLocalizedString("Series grouped for you", comment: "Onboarding: series"),
                    detail: NSLocalizedString("Volumes of one series become a collection that plays back to back.", comment: "Onboarding: series detail")
                )
            }
            .padding(.horizontal, 32)

            Button {
                withHapticFeedback { onImport() }
            } label: {
                Label(
                    importedCount > 0
                        ? String(format: NSLocalizedString("%d imported · Add more", comment: "Onboarding: import button after a pick"), importedCount)
                        : NSLocalizedString("Import Audiobook", comment: "Import button title"),
                    systemImage: importedCount > 0 ? "checkmark.circle.fill" : "plus.circle"
                )
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 6)
            }
            .buttonStyle(.glass)
        }
    }
}

struct OnboardingConnectPage: View {
    private let hardcover = HardcoverService.shared
    private let watch = WatchSyncService.shared
    @State private var hardcoverLinked = HardcoverService.shared.isLinked
    @AppStorage(SwiftDataController.iCloudSyncKey) private var iCloudSync = true

    var body: some View {
        VStack(spacing: 28) {
            OnboardingHeader(
                systemImage: "link.circle.fill",
                title: NSLocalizedString("Connect, if you like", comment: "Onboarding: integrations title"),
                text: NSLocalizedString("All of this is optional and lives in Settings too.", comment: "Onboarding: integrations body")
            )

            VStack(spacing: 0) {
                HStack {
                    OnboardingFeatureRow(
                        systemImage: "icloud",
                        title: NSLocalizedString("iCloud Sync", comment: "iCloud sync toggle"),
                        detail: NSLocalizedString("Progress and bookmarks on every device. Audio stays local.", comment: "Onboarding: iCloud detail")
                    )
                    Toggle("", isOn: $iCloudSync).labelsHidden()
                }
                .padding(16)

                Divider().padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 10) {
                    OnboardingFeatureRow(
                        systemImage: "books.vertical.circle",
                        title: NSLocalizedString("Hardcover", comment: "Hardcover integration"),
                        detail: NSLocalizedString("Sign in to track what you listen to and find series.", comment: "Onboarding: Hardcover detail")
                    )
                    if hardcoverLinked {
                        Label(
                            NSLocalizedString("Connected to Hardcover", comment: "Hardcover account row when signed in"),
                            systemImage: "checkmark.circle.fill"
                        )
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.green)
                    } else {
                        HardcoverSignInButton { hardcoverLinked = hardcover.isLinked }
                            .font(.system(size: 15, weight: .semibold))
                            .buttonStyle(.glass)
                    }
                }
                .padding(16)

                if watch.isPaired {
                    Divider().padding(.horizontal, 16)
                    OnboardingFeatureRow(
                        systemImage: "applewatch",
                        title: NSLocalizedString("Apple Watch", comment: "Apple Watch"),
                        detail: NSLocalizedString("Send a book's chapters to your watch from its page and listen without the phone.", comment: "Onboarding: watch detail")
                    )
                    .padding(16)
                }
            }
            .glassCard(cornerRadius: 22)
            .padding(.horizontal, 24)
        }
    }
}

struct OnboardingReadyPage: View {
    var body: some View {
        VStack(spacing: 28) {
            OnboardingHeader(
                systemImage: "checkmark.circle.fill",
                title: NSLocalizedString("You're set", comment: "Onboarding: ready title"),
                text: NSLocalizedString("A few things worth knowing. Tips will point them out as you go.", comment: "Onboarding: ready body")
            )

            VStack(alignment: .leading, spacing: 16) {
                OnboardingFeatureRow(
                    systemImage: "moon.fill",
                    title: NSLocalizedString("Sleep timer", comment: "Tip title: sleep timer"),
                    detail: NSLocalizedString("Minutes or end of chapter, with a fade-out.", comment: "Onboarding: sleep timer detail")
                )
                OnboardingFeatureRow(
                    systemImage: "text.alignleft",
                    title: NSLocalizedString("Read along", comment: "Tip title: transcript"),
                    detail: NSLocalizedString("On-device transcription, synced with playback.", comment: "Onboarding: transcript detail")
                )
                OnboardingFeatureRow(
                    systemImage: "text.line.first.and.arrowtriangle.forward",
                    title: NSLocalizedString("Play Queue", comment: "Play queue sheet title"),
                    detail: NSLocalizedString("Line up what plays next and reorder it.", comment: "Onboarding: queue detail")
                )
                OnboardingFeatureRow(
                    systemImage: "chart.bar.fill",
                    title: NSLocalizedString("Statistics", comment: "Statistics view title"),
                    detail: NSLocalizedString("Listening time, streaks and a monthly goal.", comment: "Onboarding: statistics detail")
                )
            }
            .padding(.horizontal, 32)
        }
    }
}
