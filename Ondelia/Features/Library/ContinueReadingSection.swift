import SwiftUI

/// One card in "Continue Reading": a lone book, or the collection a book in progress belongs
/// to — the listener is reading the series, not volume three.
enum ContinueReadingEntry: Identifiable {
    case book(AudiobookModel)
    case collection(CollectionGroup, current: AudiobookModel)

    var id: UUID {
        switch self {
        case .book(let book): return book.id
        case .collection(let group, _): return group.id
        }
    }

    /// The book that plays when the card is tapped.
    var book: AudiobookModel {
        switch self {
        case .book(let book): return book
        case .collection(_, let current): return current
        }
    }

    /// Books in progress, most recent first, each folded into its collection when it has one.
    /// A collection appears once, for the volume most recently played.
    static func build(
        books: [AudiobookModel],
        collections: [CollectionModel],
        orderedBooks: (CollectionModel) -> [AudiobookModel],
        limit: Int = 3
    ) -> [ContinueReadingEntry] {
        var entries: [ContinueReadingEntry] = []
        var seen: Set<UUID> = []
        let inProgress = books
            .filter { $0.currentPosition > 0 && !$0.isFinished }
            .sorted { $0.lastPlayed > $1.lastPlayed }
        for book in inProgress where entries.count < limit {
            guard let collection = collections.first(where: { $0.bookIDs.contains(book.id) }) else {
                entries.append(.book(book))
                continue
            }
            guard seen.insert(collection.id).inserted else { continue }
            entries.append(.collection(CollectionGroup(collection: collection, books: orderedBooks(collection)), current: book))
        }
        return entries
    }
}

/// "Continue Reading" header + horizontal card strip, shared by list and grid modes.
struct ContinueReadingSection: View {
    let entries: [ContinueReadingEntry]
    /// Horizontal padding applied to the header row (`nil` = system default).
    let headerPadding: CGFloat?
    /// Horizontal padding applied to the scrolling card row (`nil` = system default).
    let rowPadding: CGFloat?
    /// Regular width: one card in evidence and the others as small rows beside it, instead of
    /// three equal cards competing (design 7a).
    var wide = false
    let onSelect: (AudiobookModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The wide hero says "Resume" itself, so no section label over it.
            if !wide {
                SectionLabel(NSLocalizedString("Continue Reading", comment: "Section title for books in progress"))
                    .padding(.horizontal, headerPadding)
            }

            // One card takes the row, like the queue and collection cards under it; only a
            // strip of several scrolls.
            if wide, let first = entries.first {
                // Capped: on a wide Mac window a hero the width of the shelf was a bar of
                // empty glass with a play button at the far end.
                HStack(alignment: .top, spacing: 20) {
                    ContinueReadingHeroView(entry: first) { onSelect(first.book) }
                        .frame(maxWidth: 760)
                    if entries.count > 1 {
                        VStack(spacing: 9) {
                            ForEach(entries.dropFirst()) { entry in
                                ContinueReadingCompactRow(entry: entry) { onSelect(entry.book) }
                            }
                        }
                        .frame(width: 266)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, headerPadding)
            } else if entries.count == 1, let entry = entries.first {
                ContinueReadingCardView(entry: entry, fullWidth: true) { onSelect(entry.book) }
                    .padding(.horizontal, headerPadding)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(entries) { entry in
                            ContinueReadingCardView(entry: entry) { onSelect(entry.book) }
                        }
                    }
                    .padding(.horizontal, rowPadding)
                }
                // A horizontal scroll view spreads into the side safe areas by default; on
                // iPhone Duo closed those hold the vertical toolbar, so the cards would slide
                // under the "+" button. Clipped back to the safe width instead.
                .clipped()
            }
        }
    }
}

/// The small row beside the hero card: cover, title, time left, a play mark.
private struct ContinueReadingCompactRow: View {
    let entry: ContinueReadingEntry
    let onTap: () -> Void

    private var title: String {
        if case .collection(let group, _) = entry { return group.name }
        return entry.book.title ?? AudiobookModel.unknownTitle
    }

    private var remaining: TimeInterval {
        if case .collection(let group, _) = entry { return group.remaining }
        return max(entry.book.duration - entry.book.currentPosition, 0)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                CoverArtView(audiobook: entry.book, size: 38, cornerRadius: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .medium))
                        .lineLimit(1)
                    Text(String(format: NSLocalizedString("%@ left", comment: "Remaining listening time"), remaining.hoursMinutesFormatted))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(.quaternary, in: Circle())
            }
            .padding(.horizontal, 13)
            .frame(height: 53)
            .contentShape(Rectangle())
            .glassCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }
}
