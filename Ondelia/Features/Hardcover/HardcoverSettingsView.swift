import SwiftUI

/// Account and automation settings for the Hardcover integration.
struct HardcoverSettingsView: View {
    private let service = HardcoverService.shared

    @AppStorage(HardcoverService.Defaults.autoMatch) private var autoMatch = false
    @AppStorage(HardcoverService.Defaults.autoAddWantToRead) private var autoAddWantToRead = true
    @AppStorage(HardcoverService.Defaults.readingThreshold) private var readingThreshold = 1.0

    /// Mirrors `service.isLinked`, which is not observable: re-read after signing in or out.
    @State private var isLinked = false
    @State private var isRefreshing = false
    /// What the last refresh found, for the row's footer.
    @State private var lastResult: (books: Int, inSeries: Int)?

    var body: some View {
        List {
            Section {
                if isLinked {
                    Label(
                        NSLocalizedString("Connected to Hardcover", comment: "Hardcover account row when signed in"),
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(Color.primaryText)
                } else {
                    HardcoverSignInButton { isLinked = service.isLinked }
                        .foregroundStyle(Color.primaryText)
                }
            } header: {
                Text(NSLocalizedString("Account", comment: "Hardcover settings section: account"))
            } footer: {
                if !isLinked {
                    Text(NSLocalizedString(
                        "Sign in to track what you listen to on your Hardcover profile and find series.",
                        comment: "Hardcover account section footer"
                    ))
                }
            }

            Section {
                Toggle(isOn: $autoMatch) {
                    Label(
                        NSLocalizedString("Match New Books", comment: "Hardcover auto-match toggle"),
                        systemImage: "wand.and.sparkles"
                    )
                    .foregroundStyle(Color.primaryText)
                }

                Toggle(isOn: $autoAddWantToRead) {
                    Label(
                        NSLocalizedString("Add to Want to Read", comment: "Hardcover want-to-read toggle"),
                        systemImage: "bookmark"
                    )
                    .foregroundStyle(Color.primaryText)
                }
            } header: {
                Text(NSLocalizedString("Automation", comment: "Hardcover settings section: automation"))
            } footer: {
                Text(NSLocalizedString(
                    "Imported books, and server books as they join your Library, are matched to their closest Hardcover result. A book that matches the same result as another book in the same import is left unmatched.",
                    comment: "Hardcover automation section footer"
                ))
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("Started At", comment: "Hardcover reading threshold label"))
                            .foregroundStyle(Color.primaryText)
                        Spacer()
                        Text(readingThreshold / 100, format: .percent.precision(.fractionLength(0)))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(value: $readingThreshold, in: 1...99, step: 1)
                        .accessibilityLabel(NSLocalizedString(
                            "Started At", comment: "Hardcover reading threshold label"
                        ))
                        .accessibilityValue(Text(readingThreshold / 100, format: .percent.precision(.fractionLength(0))))
                }
            } header: {
                Text(NSLocalizedString("Progress", comment: "Hardcover settings section: progress"))
            } footer: {
                Text(NSLocalizedString(
                    "How far into a book counts as started. Passing it marks the book as currently reading on Hardcover; finishing it marks the book as read.",
                    comment: "Hardcover progress section footer"
                ))
            }

            if isLinked {
                Section {
                    Button {
                        withHapticFeedback {}
                        Task {
                            isRefreshing = true
                            defer { isRefreshing = false }
                            lastResult = await service.refreshMetadata(for: AudiobookManager.shared.audiobooks)
                        }
                    } label: {
                        HStack {
                            Label(
                                NSLocalizedString("Refresh All Metadata", comment: "Hardcover metadata refresh button"),
                                systemImage: "arrow.trianglehead.2.clockwise"
                            )
                            .foregroundStyle(Color.primaryText)
                            Spacer()
                            if isRefreshing { ProgressView() }
                        }
                    }
                    .disabled(isRefreshing)
                } header: {
                    Text(NSLocalizedString("Metadata", comment: "Hardcover settings section: metadata"))
                } footer: {
                    if let lastResult {
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "Refreshed %d linked books. %d belong to a series.",
                                    comment: "Hardcover metadata refresh result"
                                ),
                                lastResult.books,
                                lastResult.inSeries
                            )
                        )
                    } else {
                        Text(NSLocalizedString(
                            "Re-reads the series, summary, genres, moods and content warnings of every linked book.",
                            comment: "Hardcover metadata section footer"
                        ))
                    }
                }

                Section {
                    Button(role: .destructive) {
                        withHapticFeedback {}
                        Task {
                            await service.signOut()
                            isLinked = service.isLinked
                        }
                    } label: {
                        Text(NSLocalizedString("Sign Out", comment: "Hardcover sign-out button"))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle("Hardcover")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(TintedBackground(intensity: 0.6))
        .onAppear { isLinked = service.isLinked }
    }
}

#Preview("Hardcover Settings") {
    NavigationStack {
        HardcoverSettingsView()
    }
}
