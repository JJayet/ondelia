import SwiftUI

/// "Up Next" header + the vertical stack of queued books, for the library screen.
///
/// Reordering lives in the context menu rather than a drag: rows sit in the library's
/// `LazyVStack`, which has no `onMove`.
struct QueueSectionView: View {
    let books: [AudiobookModel]
    /// Horizontal padding applied to the header and rows (`nil` = system default).
    let horizontalPadding: CGFloat?
    let onSelect: (AudiobookModel) -> Void

    @ScaledMetric(relativeTo: .subheadline) private var coverSize: CGFloat = 44

    var body: some View {
        if !books.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(NSLocalizedString("Up Next", comment: "Section title for the play queue"))

                ForEach(Array(books.enumerated()), id: \.element.id) { index, audiobook in
                    Button {
                        withHapticFeedback { onSelect(audiobook) }
                    } label: {
                        row(audiobook)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { menu(for: index, audiobook: audiobook) }
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
    }

    @ViewBuilder
    private func row(_ audiobook: AudiobookModel) -> some View {
        HStack(spacing: 13) {
            CoverArtView(audiobook: audiobook, size: coverSize, cornerRadius: 11)

            VStack(alignment: .leading, spacing: 4) {
                Text(audiobook.title ?? AudiobookModel.unknownTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(
                    String(
                        format: NSLocalizedString("%@ · %@", comment: "Author and duration"),
                        audiobook.author ?? AudiobookModel.unknownAuthor,
                        audiobook.duration.hoursMinutesFormatted
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .glassCard()
    }

    @ViewBuilder
    private func menu(for index: Int, audiobook: AudiobookModel) -> some View {
        if index > 0 {
            Button {
                PlayQueue.shared.move(fromOffsets: [index], toOffset: index - 1)
            } label: {
                Label(
                    NSLocalizedString("Move Up", comment: "Move a book earlier in the play queue"),
                    systemImage: "arrow.up"
                )
            }
        }

        if index < books.count - 1 {
            Button {
                PlayQueue.shared.move(fromOffsets: [index], toOffset: index + 2)
            } label: {
                Label(
                    NSLocalizedString("Move Down", comment: "Move a book later in the play queue"),
                    systemImage: "arrow.down"
                )
            }
        }

        Button(role: .destructive) {
            PlayQueue.shared.remove(audiobook)
        } label: {
            Label(
                NSLocalizedString("Remove from Queue", comment: "Remove from queue button"),
                systemImage: "minus.circle"
            )
        }
        .tint(.red)
    }
}

#Preview("Queue section") {
    QueueSectionView(
        books: [PreviewContent.audiobook(), PreviewContent.audiobookLong()],
        horizontalPadding: 20,
        onSelect: { _ in }
    )
}
