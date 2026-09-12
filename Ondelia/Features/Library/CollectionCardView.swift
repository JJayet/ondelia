import SwiftUI

/// One collection on the shelf: name, count, overlapping covers and the totals. Tapping opens
/// `CollectionDetailView`, where the books, the order and the actions live.
struct CollectionCardView: View {
    let group: CollectionGroup
    let onOpen: () -> Void

    var body: some View {
        Button {
            withHapticFeedback { onOpen() }
        } label: {
            VStack(spacing: 12) {
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

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

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
            .padding(16)
            .contentShape(Rectangle())
            .glassCard(cornerRadius: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(group.name)
        .accessibilityValue(countLabel)
    }

    /// "3 volumes" or "3 of 6" for a series, "3 books" for a hand-made collection.
    var countLabel: String { group.countLabel }

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
}

extension CollectionGroup {
    /// "3 volumes" or "3 of 6" for a series, "3 books" for a hand-made collection.
    @MainActor
    var countLabel: String {
        guard isSeries else {
            return String(format: NSLocalizedString("%d books", comment: "Number of books in a collection"), books.count)
        }
        guard let total = catalogueCount, total > books.count else {
            return String(format: NSLocalizedString("%d volumes", comment: "Number of books in a series"), books.count)
        }
        return String(
            format: NSLocalizedString("%d of %d", comment: "Owned volumes out of the whole series"),
            books.count,
            total
        )
    }

    /// The author every book shares, or the first one's; nil when there is none.
    var author: String? {
        let authors = books.compactMap(\.author).filter { !$0.isEmpty }
        return authors.first
    }

    var remaining: TimeInterval {
        books.reduce(0) { $0 + max($1.duration - $1.currentPosition, 0) }
    }
}
