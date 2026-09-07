import SwiftUI

struct EnhancedAudiobookRowView: View {
    let audiobook: AudiobookModel
    let onTap: () -> Void

    /// The cover grows with the text beside it, so the row keeps its proportions at every type
    /// size instead of pinning a 56-point square next to accessibility-sized words.
    @ScaledMetric(relativeTo: .subheadline) private var coverSize: CGFloat = 56

    private var progressPercentage: Double {
        guard audiobook.duration > 0 else { return 0 }
        return audiobook.currentPosition / audiobook.duration
    }

    var body: some View {
        Button(action: { withHapticFeedback { onTap() } }) {
            HStack(spacing: 13) {
                CoverArtView(audiobook: audiobook, size: coverSize, cornerRadius: 13)

                VStack(alignment: .leading, spacing: 6) {
                    Text(audiobook.title ?? AudiobookModel.unknownTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if audiobook.currentPosition > 0 && !audiobook.isFinished {
                        ProgressLine(value: progressPercentage)
                    }

                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if audiobook.isFinished {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .glassCard()
        }
        .buttonStyle(.plain)
    }

    /// One line under the title: what state the book is in, and how much of it is left.
    private var status: String {
        let author = audiobook.author ?? AudiobookModel.unknownAuthor
        if audiobook.isFinished {
            return String(
                format: NSLocalizedString("%@ · Completed", comment: "Author and finished status"),
                author
            )
        }
        if audiobook.currentPosition > 0 {
            return String(
                format: NSLocalizedString("in progress · %@ left", comment: "Remaining listening time"),
                max(audiobook.duration - audiobook.currentPosition, 0).hoursMinutesFormatted
            )
        }
        return String(
            format: NSLocalizedString("%@ · %@", comment: "Author and duration"),
            author,
            audiobook.duration.hoursMinutesFormatted
        )
    }
}
