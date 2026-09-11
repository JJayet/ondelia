import SwiftUI

struct ContinueReadingCardView: View {
    let entry: ContinueReadingEntry
    /// Alone on its row the card fills it; in a scrolling strip each card is 320 points.
    var fullWidth = false
    let onTap: () -> Void

    private var audiobook: AudiobookModel { entry.book }

    private var group: CollectionGroup? {
        if case .collection(let group, _) = entry { return group }
        return nil
    }

    private var title: String {
        group?.name ?? audiobook.title ?? AudiobookModel.unknownTitle
    }

    /// A collection card names the volume being read; a book card names the chapter.
    private var subtitle: String? {
        if group != nil { return audiobook.title ?? AudiobookModel.unknownTitle }
        return chapterTitle
    }

    private var progressPercentage: Double {
        if let group { return group.progressFraction }
        guard audiobook.duration > 0 else { return 0 }
        return audiobook.currentPosition / audiobook.duration
    }

    private var remaining: TimeInterval {
        group?.remaining ?? max(audiobook.duration - audiobook.currentPosition, 0)
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
                    HStack(spacing: 6) {
                        if group?.isSeries == true {
                            Image(systemName: "books.vertical.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tint)
                        }
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    ProgressLine(value: progressPercentage)

                    Text(
                        String(
                            format: NSLocalizedString("%@ left", comment: "Remaining listening time"),
                            remaining.hoursMinutesFormatted
                        )
                    )
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(width: fullWidth ? nil : 320)
            .frame(maxWidth: .infinity)
            .glassCard()
        }
        .buttonStyle(.plain)
    }
}
