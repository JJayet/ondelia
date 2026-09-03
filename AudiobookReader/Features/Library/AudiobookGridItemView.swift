import SwiftUI

struct AudiobookGridItemView: View {
    let audiobook: AudiobookModel
    let onTap: () -> Void

    private var coverImage: UIImage? {
        guard let data = audiobook.coverImageData else { return nil }
        return UIImage(data: data)
    }

    private var progressPercentage: Double {
        guard audiobook.duration > 0 else { return 0 }
        return audiobook.currentPosition / audiobook.duration
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // Cover Art
                Group {
                    if let image = coverImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "book.closed")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.secondaryText)
                    }
                }
                .frame(width: 120, height: 120)
                .background(Color.secondaryBackground)
                .cornerRadius(16)
                .clipped()
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            Color.accentColor.opacity(
                                audiobook.currentPosition > 0 ? 0.3 : 0
                            ),
                            lineWidth: 2
                        )
                )

                // Book Info
                VStack(spacing: 4) {
                    Text(audiobook.title ?? AudiobookModel.unknownTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    Text(audiobook.author ?? AudiobookModel.unknownAuthor)
                        .font(.caption)
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)

                    // Progress Indicator
                    if audiobook.isFinished {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else if audiobook.currentPosition > 0 {
                        ProgressView(value: progressPercentage)
                            .progressViewStyle(
                                LinearProgressViewStyle(tint: .accentColor)
                            )
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(12)
            .glassEffect(in:.rect(cornerRadius: 20))
        }
        .buttonStyle(PlainButtonStyle())
    }
}
