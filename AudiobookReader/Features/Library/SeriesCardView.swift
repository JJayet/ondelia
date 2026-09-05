import SwiftUI

/// Says what Hardcover did to the shelf, and lets it be undone.
struct SeriesGroupingBanner: View {
    let seriesCount: Int
    let bookCount: Int
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tint)

            Text(
                String(
                    format: NSLocalizedString(
                        "%d books grouped into %d series via Hardcover",
                        comment: "Series grouping banner"
                    ),
                    bookCount,
                    seriesCount
                )
            )
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .glassCard(cornerRadius: 22)
    }
}

/// One series as the design has it: the name, how many volumes, and the volumes themselves in
/// reading order, each with its own progress.
struct SeriesCardView: View {
    let group: SeriesGroup
    let onSelect: (AudiobookModel) -> Void

    /// Collapsed series show only their spines; a series being listened to opens by itself.
    @State private var expanded: Bool?

    private var isExpanded: Bool {
        expanded ?? (group.progressFraction > 0 && group.progressFraction < 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if isExpanded {
                VStack(spacing: 10) {
                    ForEach(group.volumes) { volume in
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
        Button {
            withAnimation(.snappy(duration: 0.25)) { expanded = !isExpanded }
        } label: {
            HStack(spacing: 8) {
                Text(group.name)
                    .font(.system(size: 17, weight: .bold))
                    .lineLimit(1)

                Text(volumeCount)
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
        .accessibilityValue(volumeCount)
    }

    /// "3 volumes" on its own, or "3 of 6" once Hardcover has said how long the series is.
    private var volumeCount: String {
        guard let total = group.catalogueCount, total > group.books.count else {
            return String(
                format: NSLocalizedString("%d volumes", comment: "Number of books in a series"),
                group.books.count
            )
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
            onSelect(book)
        } label: {
            HStack(spacing: 12) {
                CoverArtView(audiobook: book, size: 52, cornerRadius: 12)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        if let badge = book.hardcover?.volumeBadge {
                            Text(badge)
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(1)
                                .foregroundStyle(book.currentPosition > 0 && !book.isFinished ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                        }
                        Text(book.title ?? AudiobookModel.unknownTitle)
                            .font(.system(size: 13.5, weight: .semibold))
                            .lineLimit(1)
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
        .accessibilityIdentifier(AccessibilityIdentifiers.Library.audiobookCell)
    }

    /// A volume Hardcover lists that the shelf does not hold.
    @ViewBuilder
    private func missingRow(_ volume: SeriesVolume) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary)
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: "questionmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

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
