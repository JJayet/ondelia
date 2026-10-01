import Foundation

/// One line of the Library list: a Library audiobook, or a server audiobook that has not
/// joined yet (ADR 0002).
enum LibraryEntry: Identifiable {
    case book(AudiobookModel)
    case server(AudiobookShelfAPI.Item)

    var id: String {
        switch self {
        case .book(let book): book.id.uuidString
        case .server(let item): "server-\(item.id)"
        }
    }

    var book: AudiobookModel? {
        if case .book(let book) = self { book } else { nil }
    }

    var narrator: String {
        if case .book(let book) = self { book.narrator ?? "" } else { "" }
    }

    var title: String {
        switch self {
        case .book(let book): book.title ?? ""
        case .server(let item): item.title
        }
    }

    var author: String {
        switch self {
        case .book(let book): book.author ?? ""
        case .server(let item): item.author ?? ""
        }
    }

    private var dateAdded: Date {
        switch self {
        case .book(let book): book.dateAdded
        case .server(let item): item.dateAdded
        }
    }

    /// `books`, already in `sort` order, with `server` woven in. `server` comes sorted too, as
    /// `AudiobookShelfCatalog.Sorted.items(for: sort)` hands it over, so this is one linear
    /// pass. Server audiobooks have never been played, so under recently played and progress
    /// they come last, by title; the other orders interleave them. The books keep exactly the
    /// order they came in.
    static func merged(
        _ books: [AudiobookModel],
        _ server: [AudiobookShelfAPI.Item],
        by sort: LibraryView.SortOption
    ) -> [LibraryEntry] {
        let left = books.map(LibraryEntry.book)
        let order: (LibraryEntry, LibraryEntry) -> Bool
        switch sort {
        case .lastPlayed, .progress, .title:
            order = byTitle
        case .author:
            order = { lhs, rhs in
                let names = lhs.author.localizedStandardCompare(rhs.author)
                return names == .orderedSame ? byTitle(lhs, rhs) : names == .orderedAscending
            }
        case .dateAdded:
            order = { lhs, rhs in lhs.dateAdded == rhs.dateAdded ? byTitle(lhs, rhs) : lhs.dateAdded > rhs.dateAdded }
        }
        let right = server.map(LibraryEntry.server)
        if sort == .lastPlayed || sort == .progress { return left + right }

        var result: [LibraryEntry] = []
        result.reserveCapacity(left.count + right.count)
        var i = 0, j = 0
        while i < left.count, j < right.count {
            if order(right[j], left[i]) {
                result.append(right[j]); j += 1
            } else {
                result.append(left[i]); i += 1
            }
        }
        return result + left[i...] + right[j...]
    }

    private static func byTitle(_ lhs: LibraryEntry, _ rhs: LibraryEntry) -> Bool {
        lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}
