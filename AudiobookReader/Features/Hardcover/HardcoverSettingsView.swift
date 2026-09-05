import SwiftUI

/// Account and automation settings for the Hardcover integration.
struct HardcoverSettingsView: View {
    private let service = HardcoverService.shared

    @AppStorage(HardcoverService.Defaults.autoMatch) private var autoMatch = false
    @AppStorage(HardcoverService.Defaults.autoAddWantToRead) private var autoAddWantToRead = true
    @AppStorage(HardcoverService.Defaults.readingThreshold) private var readingThreshold = 1.0

    /// The token is held in the keychain, so the field keeps its own copy while editing.
    @State private var token = ""
    @FocusState private var tokenFocused: Bool

    var body: some View {
        List {
            Section {
                TextField(
                    "Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXV…",
                    text: $token,
                    axis: .vertical
                )
                .lineLimit(1...3)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($tokenFocused)
                .font(.footnote.monospaced())
                .accessibilityLabel(NSLocalizedString(
                    "Hardcover access token",
                    comment: "Accessibility label for the Hardcover token field"
                ))
                .onChange(of: token) { _, newValue in
                    service.token = newValue
                }
            } header: {
                Text(NSLocalizedString("Access Token", comment: "Hardcover settings section: token"))
            } footer: {
                Text(NSLocalizedString(
                    "Create a token at hardcover.app under Settings → API, then paste it here.",
                    comment: "Hardcover token section footer"
                ))
            }

            Section {
                Toggle(isOn: $autoMatch) {
                    Label(
                        NSLocalizedString("Match Imported Books", comment: "Hardcover auto-match toggle"),
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
                    "Imported books are matched to their closest Hardcover result. A book that matches the same result as another book in the same import is left unmatched.",
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

            if !token.isEmpty {
                Section {
                    Button(role: .destructive) {
                        token = ""
                        tokenFocused = false
                    } label: {
                        Text(NSLocalizedString("Remove Token", comment: "Hardcover unlink button"))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle("Hardcover")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color.primaryBackground)
        .onAppear { token = service.token ?? "" }
    }
}

#Preview("Hardcover Settings") {
    NavigationStack {
        HardcoverSettingsView()
    }
}
