import SwiftUI

struct EnhancedAudiobookRowView: View {
    let audiobook: AudiobookModel
    let onTap: () -> Void

    private var progressPercentage: Double {
        guard audiobook.duration > 0 else { return 0 }
        return audiobook.currentPosition / audiobook.duration
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 13) {
                CoverArtView(audiobook: audiobook, size: 56, cornerRadius: 13)

                VStack(alignment: .leading, spacing: 6) {
                    Text(audiobook.title ?? AudiobookModel.unknownTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if audiobook.currentPosition > 0 && !audiobook.isFinished {
                        ProgressLine(value: progressPercentage)
                    }

                    Text(status)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if audiobook.isFinished {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
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
