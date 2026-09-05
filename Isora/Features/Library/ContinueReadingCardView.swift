import SwiftUI

struct ContinueReadingCardView: View {
    let audiobook: AudiobookModel
    let onTap: () -> Void

    private var progressPercentage: Double {
        guard audiobook.duration > 0 else { return 0 }
        return audiobook.currentPosition / audiobook.duration
    }

    /// The chapter the position falls in, so the card says where the book was left rather than
    /// only how far through it is.
    private var chapterTitle: String? {
        let position = audiobook.currentPosition
        let chapter = audiobook.sortedChapters.last { position >= $0.startTime }
        guard let chapter else { return nil }
        return chapter.title
            ?? String(
                format: NSLocalizedString("Chapter %d", comment: "Default chapter title with number"),
                chapter.chapterNumber
            )
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                CoverArtView(audiobook: audiobook, size: 84)

                VStack(alignment: .leading, spacing: 8) {
                    Text(audiobook.title ?? AudiobookModel.unknownTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let chapterTitle {
                        Text(chapterTitle)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    ProgressLine(value: progressPercentage)

                    Text(
                        String(
                            format: NSLocalizedString("%@ left", comment: "Remaining listening time"),
                            max(audiobook.duration - audiobook.currentPosition, 0).hoursMinutesFormatted
                        )
                    )
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(width: 320)
            .glassCard()
        }
        .buttonStyle(.plain)
    }
}
