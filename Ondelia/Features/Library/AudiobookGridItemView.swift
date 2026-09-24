import SwiftUI

struct AudiobookGridItemView: View {
    let audiobook: AudiobookModel
    var columns: Int = 2
    let onTap: () -> Void

    private var titleFontSize: CGFloat { columns >= 3 ? 11.5 : 12.5 }
    private var metaFontSize: CGFloat { columns >= 3 ? 10 : 11 }

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
        Button(action: { withHapticFeedback { onTap() } }) {
            VStack(alignment: .leading, spacing: 8) {
                CoverArtView(audiobook: audiobook, size: nil)
                    .overlay(alignment: .topLeading) {
                        if !AudiobookManager.shared.hasFile(audiobook) {
                            Image(systemName: "icloud.and.arrow.down")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(6)
                                .background(.black.opacity(0.45), in: Circle())
                                .foregroundStyle(.white)
                                .padding(6)
                                .accessibilityLabel(NSLocalizedString("Not on this device", comment: "Missing audio badge"))
                        }
                    }
                    // The progress hairline rides the bottom edge of the artwork itself.
                    .overlay(alignment: .bottom) {
                        if audiobook.currentPosition > 0 {
                            ProgressLine(
                                value: progressPercentage,
                                height: 3,
                                color: audiobook.isFinished ? .green : nil
                            )
                        }
                    }

                Text(audiobook.title ?? AudiobookModel.unknownTitle)
                    .font(.system(size: titleFontSize, weight: .semibold))
                    .lineLimit(columns >= 4 ? 1 : 2)
                    .multilineTextAlignment(.leading)

                if columns < 4 {
                    HStack(spacing: 4) {
                        Text(meta)
                            .font(.system(size: metaFontSize))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if audiobook.hardcover != nil {
                            HardcoverLinkMark(size: metaFontSize - 1)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
