import Foundation

extension AudiobookShelfCatalog {
    /// The server's books in each order the Library sorts by.
    struct Sorted: Sendable {
        var byTitle: [AudiobookShelfAPI.Item] = []
        var byAuthor: [AudiobookShelfAPI.Item] = []
        var byDateAdded: [AudiobookShelfAPI.Item] = []

        init() {}

        nonisolated init(_ items: [AudiobookShelfAPI.Item]) {
            func titleOrder(_ lhs: AudiobookShelfAPI.Item, _ rhs: AudiobookShelfAPI.Item) -> Bool {
                lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            byTitle = items.sorted(by: titleOrder)
            byAuthor = byTitle.sorted { lhs, rhs in
                let names = (lhs.author ?? "").localizedStandardCompare(rhs.author ?? "")
                return names == .orderedSame ? titleOrder(lhs, rhs) : names == .orderedAscending
            }
            byDateAdded = byTitle.sorted { lhs, rhs in
                lhs.dateAdded == rhs.dateAdded ? titleOrder(lhs, rhs) : lhs.dateAdded > rhs.dateAdded
            }
        }

        /// The order `LibraryEntry.merged` expects for `sort`.
        func items(for sort: LibraryView.SortOption) -> [AudiobookShelfAPI.Item] {
            switch sort {
            case .author: byAuthor
            case .dateAdded: byDateAdded
            case .title, .lastPlayed, .progress: byTitle
            }
        }
    }
}
