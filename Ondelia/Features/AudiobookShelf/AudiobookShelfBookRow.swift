import SwiftUI

/// A server book that has not joined the Library, drawn like `EnhancedAudiobookRowView` so it
/// sits in the Library list beside the books that have. Tapping streams it, which makes it
/// join; a long press downloads it.
struct AudiobookShelfBookRow: View {
    let item: AudiobookShelfAPI.Item

    @Environment(\.audiobookShelfPlay) private var play
    @ScaledMetric(relativeTo: .subheadline) private var coverSize: CGFloat = 56
    private let service = AudiobookShelfService.shared

    var body: some View {
        Button {
            withHapticFeedback { service.play(item, local: nil, with: play) }
        } label: {
            HStack(spacing: 13) {
                AudiobookShelfCover(item: item.id, title: item.title, size: coverSize, cornerRadius: 13)
                    .overlay { transferOverlay }

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title.isEmpty ? AudiobookModel.unknownTitle : item.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if service.preparingStreams.contains(item.id) {
                    ProgressView()
                } else {
                    Image(systemName: "icloud")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(NSLocalizedString("On the server", comment: "Server audiobook not in the Library"))
                }
            }
            .padding(16)
            .glassCard()
        }
        .buttonStyle(.plain)
        .contextMenu { AudiobookShelfItemMenu(item: item, isOnDevice: false) }
    }

    private var status: String {
        String(
            format: NSLocalizedString("%@ · %@", comment: "Author and duration"),
            item.author ?? AudiobookModel.unknownAuthor,
            (item.media.duration ?? 0).hoursMinutesFormatted
        )
    }

    @ViewBuilder private var transferOverlay: some View {
        if let progress = service.downloads[item.id] {
            AudiobookShelfTransferOverlay(fraction: progress.fraction)
        } else if service.importing.contains(item.id) {
            AudiobookShelfTransferOverlay(fraction: nil)
        }
    }
}
