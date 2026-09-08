import SwiftUI

extension PlayerView {
    // MARK: - Up next
    //
    // What comes after the chapter playing, plus the sleep timer when one is running — the two
    // things a listener checks without leaving the player.
    @ViewBuilder
    var upNextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let origin = audioManager.undoSeekOrigin {
                Button {
                    withHapticFeedback { audioManager.undoLastSeek() }
                } label: {
                    undoSeekRow(origin)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 4)
                .accessibilityIdentifier(AccessibilityIdentifiers.Player.undoSeekRow)
            }

            if !upNextChapters.isEmpty {
                SectionLabel(NSLocalizedString("Up next", comment: "Player: next chapters section"))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 2)

                ForEach(upNextChapters, id: \.id) { chapter in
                    Button {
                        withHapticFeedback { audioManager.seek(to: chapter.startTime) }
                    } label: {
                        upNextRow(chapter)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let next = nextQueuedBook {
                Button {
                    withHapticFeedback {
                        audioManager.loadAudiobook(next)
                        audioManager.startPlaybackAfterOpeningBook()
                        PlayQueue.shared.remove(next)
                    }
                } label: {
                    nextBookRow(next)
                }
                .buttonStyle(.plain)
            }

            if sleepTimeRemaining > 0 {
                Menu { sleepTimerMenuItems } label: { sleepTimerRow }
                    .simultaneousGesture(TapGesture().onEnded { withHapticFeedback {} })
                    .buttonStyle(.plain)
                    .padding(.top, 4)
            }
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.Player.upNextSection)
    }

    /// The two chapters after the one playing — the whole list when nothing is playing yet.
    var upNextChapters: [ChapterModel] {
        guard let current = currentChapter,
              let index = chapters.firstIndex(where: { $0.id == current.id }) else {
            return Array(chapters.prefix(2))
        }
        return Array(chapters.dropFirst(index + 1).prefix(2))
    }

    /// The book the play queue would start once this one ends — hidden when it is this book.
    /// What starts when this book ends, the same way `handlePlaybackEnded` decides it: a
    /// collection playing back to back names the next book; otherwise the play queue's head.
    var nextQueuedBook: AudiobookModel? {
        if let chained = audiobookManager.nextBook(after: audiobook) { return chained }
        guard let next = PlayQueue.shared.books(in: audiobookManager.audiobooks).first,
              next.id != audiobook.id else { return nil }
        return next
    }

    @ViewBuilder
    private func upNextRow(_ chapter: ChapterModel) -> some View {
        row(
            title: chapterTitle(chapter),
            trailing: max(chapter.endTime - chapter.startTime, 0).hoursMinutesFormatted
        ) {
            Text(verbatim: "\(chapter.chapterNumber)")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func nextBookRow(_ book: AudiobookModel) -> some View {
        row(
            title: String(
                format: NSLocalizedString("Next: %@", comment: "Player: next queued book"),
                book.title ?? AudiobookModel.unknownTitle
            ),
            trailing: book.duration.hoursMinutesFormatted
        ) {
            Image(systemName: "text.line.first.and.arrowtriangle.forward")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
    }

    /// One row of the up-next list: a small leading marker, a title, a duration.
    @ViewBuilder
    private func row<Leading: View>(
        title: String,
        trailing: String,
        @ViewBuilder leading: () -> Leading
    ) -> some View {
        HStack(spacing: 12) {
            leading()

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 8)

            Text(trailing)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .glassCard(cornerRadius: 18)
        .contentShape(Rectangle())
    }

    /// "Back to 12:34", offered for a minute after a jump the listener may not have meant.
    private func undoSeekRow(_ origin: TimeInterval) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tint)

            Text(String(
                format: NSLocalizedString("Back to %@", comment: "Player: undo the last seek, with the position it left"),
                origin.clockFormatted
            ))
            .font(.system(size: 13, weight: .medium))
            .monospacedDigit()

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .glassCard(cornerRadius: 18)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var sleepTimerRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.tint)
                .frame(width: 8, height: 8)

            Text(
                String(
                    format: NSLocalizedString(
                        "Stops in %@",
                        comment: "Player: time left on the sleep timer"
                    ),
                    sleepTimeRemaining.hoursMinutesFormatted
                )
            )
            .font(.system(size: 13, weight: .medium))
            .monospacedDigit()

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .glassCard(cornerRadius: 18)
        .contentShape(Rectangle())
        .accessibilityIdentifier(AccessibilityIdentifiers.Player.sleepTimerRow)
    }
}
