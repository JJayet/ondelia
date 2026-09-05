import SwiftUI

struct AudiobookGridItemView: View {
    let audiobook: AudiobookModel
    let onTap: () -> Void

    private var progressPercentage: Double {
        guard audiobook.duration > 0 else { return 0 }
        return audiobook.currentPosition / audiobook.duration
    }

    private var meta: String {
        audiobook.isFinished
            ? String(
                format: NSLocalizedString("Completed · %@", comment: "Finished book with its duration"),
                audiobook.duration.hoursMinutesFormatted
            )
            : String(
                format: NSLocalizedString("%d%% · %@", comment: "Progress percentage and duration"),
                Int(progressPercentage * 100),
                audiobook.duration.hoursMinutesFormatted
            )
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                CoverArtView(audiobook: audiobook, size: nil)
                    // The progress hairline rides the bottom edge of the artwork itself.
                    .overlay(alignment: .bottom) {
                        if audiobook.currentPosition > 0 {
                            ProgressLine(
                                value: progressPercentage,
                                height: 3,
                                color: audiobook.isFinished ? .green : .accentColor
                            )
                        }
                    }

                Text(audiobook.title ?? AudiobookModel.unknownTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(meta)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
