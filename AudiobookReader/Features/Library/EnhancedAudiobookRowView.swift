import SwiftUI

struct EnhancedAudiobookRowView: View {
    let audiobook: AudiobookModel
    let onTap: () -> Void

    private var coverImage: UIImage? {
        CoverImageCache.image(for: audiobook)
    }

    private var progressPercentage: Double {
        guard audiobook.duration > 0 else { return 0 }
        return audiobook.currentPosition / audiobook.duration
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Cover Art
                Group {
                    if let image = coverImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "book.closed")
                            .font(.title2)
                            .foregroundStyle(Color.secondaryText)
                    }
                }
                .frame(width: 70, height: 105)
                .background(Color.secondaryBackground)
                .clipShape(.rect(cornerRadius: 12))
                .clipped()
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)

                // Book Info
                VStack(alignment: .leading, spacing: 6) {
                    Text(audiobook.title ?? AudiobookModel.unknownTitle)
                        .font(.headline)
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(audiobook.author ?? AudiobookModel.unknownAuthor)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)

                    // Progress Section
                    HStack {
                        if audiobook.isFinished {
                            Label(
                                NSLocalizedString(
                                    "Completed",
                                    comment: "Audiobook completed status"
                                ),
                                systemImage: "checkmark.circle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.green)
                        } else if audiobook.currentPosition > 0 {
                            VStack(alignment: .leading, spacing: 4) {
                                ProgressView(value: progressPercentage)
                                    .progressViewStyle(
                                        LinearProgressViewStyle(
                                            tint: .accentColor
                                        )
                                    )
                                    .frame(height: 3)

                                Text(
                                    String(
                                        format: NSLocalizedString(
                                            "%d%% complete",
                                            comment: "Progress percentage"
                                        ),
                                        Int(progressPercentage * 100)
                                    )
                                )
                                .font(.caption2)
                                .foregroundStyle(Color.secondaryText)
                            }
                        } else {
                            Text(
                                NSLocalizedString(
                                    "Not Started",
                                    comment: "Audiobook not started status"
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(Color.secondaryText)
                        }

                        Spacer()

                        Text(audiobook.duration.hoursMinutesFormatted)
                            .font(.caption)
                            .foregroundStyle(Color.secondaryText)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText)
            }
            .padding(16)
            .glassEffect(in:.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

}
