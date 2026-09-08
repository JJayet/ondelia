import SwiftUI

/// One collection on the shelf: the name, how many books, and the books themselves, each with
/// its own progress. A series card can also list the volumes Hardcover knows that the shelf lacks.
struct CollectionCardView: View {
    let group: CollectionGroup
    let showMissing: Bool
    let bookActions: BookActions
    let onSelect: (AudiobookModel) -> Void
    let onRename: (CollectionModel) -> Void
    let onDelete: (CollectionModel) -> Void
    let onRemoveBook: (AudiobookModel, CollectionModel) -> Void

    /// Collapsed cards show only their spines; one being listened to opens by itself.
    @State private var expanded: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isExpanded: Bool {
        expanded ?? (group.progressFraction > 0 && group.progressFraction < 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if isExpanded {
                VStack(spacing: 10) {
                    ForEach(group.volumes(showMissing: showMissing)) { volume in
                        switch volume {
                        case .owned(let book): volumeRow(book)
                        case .missing(let listing): missingRow(listing)
                        }
                    }
                }
                .padding(.top, 14)
            } else {
                spines.padding(.top, 12)
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 28)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                withHapticFeedback {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { expanded = !isExpanded }
                }
            } label: {
                HStack(spacing: 8) {
                    if group.isSeries {
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tint)
                    }
                    Text(group.name)
                        .font(.system(size: 17, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(countLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(.quaternary, in: Capsule())

                    Spacer(minLength: 0)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(group.name)
            .accessibilityValue(countLabel)

            Menu {
                // A series takes its name from Hardcover, so only hand-made collections rename.
                if !group.isSeries {
                    Button { onRename(group.collection) } label: {
                        Label(NSLocalizedString("Rename", comment: "Rename button"), systemImage: "pencil")
                    }
                }
                Button(role: .destructive) { onDelete(group.collection) } label: {
                    Label(NSLocalizedString("Delete Collection", comment: "Delete a collection, keeping its books"), systemImage: "trash")
                }
                .tint(.red)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("More", comment: "Book actions menu"))
        }
    }

    /// "3 volumes" or "3 of 6" for a series, "3 books" for a hand-made collection.
    private var countLabel: String {
        guard group.isSeries else {
            return String(format: NSLocalizedString("%d books", comment: "Number of books in a collection"), group.books.count)
        }
        guard let total = group.catalogueCount, total > group.books.count else {
            return String(format: NSLocalizedString("%d volumes", comment: "Number of books in a series"), group.books.count)
        }
        return String(
            format: NSLocalizedString("%d of %d", comment: "Owned volumes out of the whole series"),
            group.books.count,
            total
        )
    }

    /// The collapsed state: overlapping covers, then the totals.
    private var spines: some View {
        HStack(spacing: 13) {
            HStack(spacing: -14) {
                ForEach(Array(group.books.prefix(3)), id: \.id) { book in
                    CoverArtView(audiobook: book, size: 44, cornerRadius: 8)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(group.totalDuration.hoursMinutesFormatted)
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    private var subtitle: String {
        guard let current = group.currentBook, current.currentPosition > 0 else {
            return String(
                format: NSLocalizedString("%d%% of the series", comment: "Series progress"),
                Int(group.progressFraction * 100)
            )
        }
        return String(
            format: NSLocalizedString("%@ in progress", comment: "Volume currently being listened to"),
            current.title ?? AudiobookModel.unknownTitle
        )
    }

    @ViewBuilder
    private func volumeRow(_ book: AudiobookModel) -> some View {
        Button {
            withHapticFeedback { onSelect(book) }
        } label: {
            HStack(spacing: 12) {
                CoverArtView(audiobook: book, size: 52, cornerRadius: 12)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        if group.isSeries, let badge = book.hardcover?.volumeBadge {
                            Text(badge)
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(1)
                                .foregroundStyle(book.currentPosition > 0 && !book.isFinished ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                        }
                        Text(book.title ?? AudiobookModel.unknownTitle)
                            .font(.system(size: 13.5, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    if book.currentPosition > 0 && !book.isFinished {
                        ProgressLine(value: book.progressFraction)
                    }

                    Text(status(book))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            BookActionsMenu(audiobook: book, actions: bookActions)
            // Series membership is Hardcover's call; only a hand-made collection lets go of a book.
            if !group.isSeries {
                Divider()
                Button { onRemoveBook(book, group.collection) } label: {
                    Label(NSLocalizedString("Remove from Collection", comment: "Take a book out of a collection"), systemImage: "minus.circle")
                }
            }
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.Library.audiobookCell)
    }

    /// A volume Hardcover lists that the shelf does not hold.
    @ViewBuilder
    private func missingRow(_ volume: SeriesVolume) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: volume.artworkURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "questionmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(0.7)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    if let badge = volume.badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(.tertiary)
                    }
                    Text(volume.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Text(NSLocalizedString("Not in your library", comment: "Series volume the reader does not own"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func status(_ book: AudiobookModel) -> String {
        if book.isFinished {
            return String(
                format: NSLocalizedString("Completed · %@", comment: "Finished book with its duration"),
                book.duration.hoursMinutesFormatted
            )
        }
        if book.currentPosition > 0 {
            return String(
                format: NSLocalizedString("in progress · %@ left", comment: "Remaining listening time"),
                max(book.duration - book.currentPosition, 0).hoursMinutesFormatted
            )
        }
        return book.duration.hoursMinutesFormatted
    }
}
