import SwiftUI

// MARK: - Progress
extension BookDetailView {
    /// `sheets`: the Chapters and Bookmarks buttons; around the fold those are tabs instead.
    func progressCard(sheets: Bool = true) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(
                    String(
                        format: NSLocalizedString("%d%% listened", comment: "Percent of the book heard"),
                        Int(audiobook.progressFraction * 100)
                    )
                )
                .font(.system(size: 13.5, weight: .semibold))

                Spacer()

                Text(
                    String(
                        format: NSLocalizedString("%@ left", comment: "Remaining listening time"),
                        remaining.hoursMinutesFormatted
                    )
                )
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
            }
            .padding(.bottom, 10)

            ProgressLine(value: audiobook.progressFraction, height: 6)

            if AudiobookManager.shared.hasFile(audiobook) {
                resumeButton
            } else if AudiobookShelfService.shared.canStream(audiobook) {
                // Plays from the server; the download keeps this entry and its position.
                resumeButton
                AudiobookShelfDownloadButton(book: audiobook)
                    .padding(.top, 10)
            } else {
                Label(
                    NSLocalizedString("Not on this device", comment: "Missing audio badge"),
                    systemImage: "icloud.and.arrow.down"
                )
                .font(.system(size: 15.5, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .glassEffect(.regular, in: Capsule())
                .padding(.top, 16)

                Text(NSLocalizedString(
                    "Import the same audio file on this device to play it here.",
                    comment: "Missing audio explanation"
                ))
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            }

            if sheets {
                HStack(spacing: 10) {
                    Button { withHapticFeedback { showingChapters = true } } label: {
                        secondaryLabel(NSLocalizedString("Chapters", comment: "Chapter list sheet title"))
                    }
                    .buttonStyle(.plain)
                    .disabled(chapters.isEmpty)

                    Button { withHapticFeedback { showingBookmarks = true } } label: {
                        secondaryLabel(NSLocalizedString("Bookmarks", comment: "Bookmarks button title"))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 10)
            }

            WatchSendRowView(audiobook: audiobook)
                .padding(.top, 10)
        }
        .padding(18)
        .glassCard(cornerRadius: 28)
    }

    private var resumeButton: some View {
        Button(action: play) {
            HStack(spacing: 9) {
                Image(systemName: "play.fill").font(.system(size: 14, weight: .bold))
                Text(
                    audiobook.currentPosition > 0
                        ? String(
                            format: NSLocalizedString("Resume at %@", comment: "Resume playback at a timestamp"),
                            audiobook.currentPosition.clockFormatted
                        )
                        : NSLocalizedString("Play", comment: "Play playback accessibility label")
                )
                .font(.system(size: 15.5, weight: .semibold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(.tint, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
        .accessibilityIdentifier(AccessibilityIdentifiers.Library.resumeButton)
    }

    private func secondaryLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13.5, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .glassEffect(.regular, in: Capsule())
    }
}
