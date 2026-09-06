import SwiftUI

extension PlayerView {
    // MARK: - Up next
    //
    // What comes after the chapter playing, plus the sleep timer when one is running — the two
    // things a listener checks without leaving the player.
    @ViewBuilder
    var upNextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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

    @ViewBuilder
    private func upNextRow(_ chapter: ChapterModel) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: "\(chapter.chapterNumber)")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.tertiary)

            Text(chapterTitle(chapter))
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 8)

            Text(max(chapter.endTime - chapter.startTime, 0).hoursMinutesFormatted)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
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
