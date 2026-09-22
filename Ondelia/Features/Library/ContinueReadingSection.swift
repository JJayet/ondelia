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
    let onSelect: (AudiobookModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(NSLocalizedString("Continue Reading", comment: "Section title for books in progress"))
                .padding(.horizontal, headerPadding)

            // One card takes the row, like the queue and collection cards under it; only a
            // strip of several scrolls.
            if entries.count == 1, let entry = entries.first {
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
