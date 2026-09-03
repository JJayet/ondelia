import SwiftUI

struct ContinueReadingCardView: View {
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
            VStack(alignment: .leading, spacing: 12) {
                // Cover Art
                Group {
                    if let image = coverImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "book.closed")
                            .font(.system(size: 30))
                            .foregroundStyle(Color.secondaryText)
                    }
                }
                .frame(width: 140, height: 100)
                .background(Color.secondaryBackground)
                .cornerRadius(12)
                .clipped()

                VStack(alignment: .leading, spacing: 6) {
                    Text(audiobook.title ?? AudiobookModel.unknownTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(2)

                    ProgressView(value: progressPercentage)
                        .progressViewStyle(
                            LinearProgressViewStyle(tint: .accentColor)
                        )
                        .frame(height: 3)

                    Text(
                        String(
                            format: NSLocalizedString("%d%% complete", comment: "Progress percentage"),
                            Int(progressPercentage * 100)
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(Color.secondaryText)
                }
            }
            .frame(width: 140)
            .padding(12)
            .glassEffect(in:.rect(cornerRadius: 16))
        }
        .buttonStyle(PlainButtonStyle())
    }
}
