import SwiftUI

// MARK: - The books
extension CollectionDetailView {
    var booksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(group.isSeries
                ? NSLocalizedString("Volumes", comment: "Collection detail: series books section")
                : NSLocalizedString("Books", comment: "Collection detail: books section"))
                .padding(.horizontal, 8)
                .padding(.top, 8)

            ForEach(group.volumes(showMissing: showMissing)) { volume in
                switch volume {
                case .owned(let book): bookRow(book)
                case .missing(let listing): missingRow(listing)
                }
            }
        }
    }

    private var isManual: Bool { collection.sort == .manual }

    @ViewBuilder
    private func bookRow(_ book: AudiobookModel) -> some View {
        let index = group.books.firstIndex { $0.id == book.id } ?? 0
        let isCurrent = group.currentBook?.id == book.id && book.currentPosition > 0
        Button {
            withHapticFeedback { onSelectBook(book) }
        } label: {
            HStack(spacing: 12) {
                CoverArtView(audiobook: book, size: 48, cornerRadius: 11)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(volumeLabel(book, index: index)) · \(book.title ?? AudiobookModel.unknownTitle)")
                        .font(.system(size: 14.5, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(status(book))
                        .font(.system(size: 11.5))
                        .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isCurrent {
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tint)
                } else if book.isFinished {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                }
            }
            .padding(14)
            .contentShape(Rectangle())
            .glassCard(cornerRadius: 22)
            .overlay {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.tint.opacity(0.5), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            BookActionsMenu(audiobook: book, actions: bookActions)
            Divider()
            // Reachable without a drag, and the only way with VoiceOver. Picking one on a sorted
            // collection switches it to manual order.
            Button { withHapticFeedback { manager.move(book, by: -1, in: collection) } } label: {
                Label(NSLocalizedString("Move Up", comment: "Move a book one step up in a collection"), systemImage: "arrow.up")
            }
            .disabled(isManual && index == 0)
            Button { withHapticFeedback { manager.move(book, by: 1, in: collection) } } label: {
                Label(NSLocalizedString("Move Down", comment: "Move a book one step down in a collection"), systemImage: "arrow.down")
            }
            .disabled(isManual && index == group.books.count - 1)
            // Series membership is Hardcover's call; only a hand-made collection lets go of a book.
            if !group.isSeries {
                Button { manager.remove(book, from: collection) } label: {
                    Label(NSLocalizedString("Remove from Collection", comment: "Take a book out of a collection"), systemImage: "minus.circle")
                }
            }
        }
        // Drag to reorder, in manual order only: a sorted list would snap straight back.
        .draggable(book.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard isManual, let id = items.first.flatMap(UUID.init),
                  let dragged = group.books.first(where: { $0.id == id }) else { return false }
            withHapticFeedback { manager.move(dragged, before: book, in: collection) }
            return true
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.Library.audiobookCell)
    }

    /// "in progress · ch. 14 of 42", "Downloaded · 23h 44m", "Completed · …" or "Not on this device".
    private func status(_ book: AudiobookModel) -> String {
        if book.isFinished {
            return String(format: NSLocalizedString("Completed · %@", comment: "Finished book with its duration"), book.duration.hoursMinutesFormatted)
        }
        if book.currentPosition > 0 {
            if let chapter = currentChapterNumber(of: book) {
                return String(
                    format: NSLocalizedString("in progress · ch. %d of %d", comment: "Collection row: chapter position"),
                    chapter,
                    book.sortedChapters.count
                )
            }
            return String(
                format: NSLocalizedString("in progress · %@ left", comment: "Remaining listening time"),
                max(book.duration - book.currentPosition, 0).hoursMinutesFormatted
            )
        }
        guard manager.hasFile(book) else {
            return NSLocalizedString("Not on this device", comment: "Missing audio badge")
        }
        return String(format: NSLocalizedString("Downloaded · %@", comment: "Collection row: unplayed book on this device"), book.duration.hoursMinutesFormatted)
    }

    /// A volume Hardcover lists that the shelf does not hold.
    @ViewBuilder
    private func missingRow(_ volume: SeriesVolume) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: volume.artworkURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "questionmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .opacity(0.7)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(volume.badge ?? "") · \(volume.title)")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(NSLocalizedString("Not in your library", comment: "Series volume the reader does not own"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .glassCard(cornerRadius: 22)
        .opacity(0.8)
        .accessibilityElement(children: .combine)
    }
}
