import Foundation

/// One collection as the shelf shows it: the stored collection plus the books it resolves to,
/// in the collection's order, after the library's filter.
struct CollectionGroup: Identifiable {
    /// Settings key: whether a series card lists the volumes Hardcover knows that the shelf lacks.
    static let showMissingKey = "library.showMissingSeriesBooks"

    let collection: CollectionModel
    let books: [AudiobookModel]

    var id: UUID { collection.id }
    var name: String { collection.name }
    var seriesID: Int? { collection.hardcoverSeriesID }
    var isSeries: Bool { collection.isSeries }

    var totalDuration: TimeInterval {
        books.reduce(0) { $0 + $1.duration }
    }

    /// Progress across the whole collection, weighted by length — so a finished short volume
    /// does not read as more progress than half of a long one.
    var progressFraction: Double {
        let total = totalDuration
        guard total > 0 else { return 0 }
        return books.reduce(0) { $0 + $1.currentPosition } / total
    }

    /// Started and not finished: the strip and the "Recent" sort put these first.
    var isInProgress: Bool { progressFraction > 0 && progressFraction < 1 }

    /// When any of its books was last played.
    var lastPlayed: Date { books.map(\.lastPlayed).max() ?? .distantPast }

    /// The book being listened to, if any: the first unfinished book with progress, else the
    /// first unfinished one.
    var currentBook: AudiobookModel? {
        books.first { $0.currentPosition > 0 && !$0.isFinished } ?? books.first { !$0.isFinished }
    }

    /// One entry in the card.
    enum Volume: Identifiable {
        case owned(AudiobookModel)
        /// A volume Hardcover lists that the library does not hold.
        case missing(SeriesVolume)
        /// A server series' book that has not joined the Library; it plays from the server.
        case server(AudiobookShelfAPI.Item)

        var id: String {
            switch self {
            case .owned(let book): return book.id.uuidString
            case .missing(let volume): return "hardcover-\(volume.bookID)"
            case .server(let item): return "server-\(item.id)"
            }
        }

        var sortKey: Double {
            switch self {
            case .owned(let book): return book.hardcover?.seriesPosition ?? .greatestFiniteMagnitude
            case .missing(let volume): return volume.position ?? .greatestFiniteMagnitude
            case .server: return .greatestFiniteMagnitude
            }
        }
    }

    /// The server series this Collection stands for, while the server's audiobooks are shown.
    @MainActor
    var serverSeries: AudiobookShelfAPI.Series? {
        AudiobookShelfCatalog.shared.seriesByCollection[collection.id]
    }

    /// The card's rows. A server series lists every book the server has in it, in series
    /// order, those in the Library resolved to the books themselves. A Hardcover series with
    /// `showMissing` on lists Hardcover's whole catalogue the same way; otherwise just the
    /// books, in order.
    @MainActor
    func volumes(showMissing: Bool) -> [Volume] {
        if let serverSeries {
            let linked = AudiobookShelfService.shared.libraryBooks
            let shown = Dictionary(books.map { ($0.id, $0) }) { first, _ in first }
            let members = (serverSeries.books ?? []).compactMap { item -> Volume? in
                guard let book = linked[item.id] else { return .server(item) }
                return shown[book.id].map(Volume.owned)
            }
            // A Library book the listener added by hand that the server does not list.
            let listed = Set(members.compactMap { volume -> UUID? in
                if case .owned(let book) = volume { book.id } else { nil }
            })
            return members + books.filter { !listed.contains($0.id) }.map(Volume.owned)
        }
        guard showMissing, let seriesID else { return books.map(Volume.owned) }
        let catalogue = SeriesCatalog.volumes(for: seriesID)
        guard !catalogue.isEmpty else { return books.map(Volume.owned) }

        let ownedByBookID = Dictionary(
            books.compactMap { book in book.hardcover.map { ($0.id, book) } },
            uniquingKeysWith: { first, _ in first }
        )
        var entries = catalogue.map { volume in
            ownedByBookID[volume.bookID].map(Volume.owned) ?? .missing(volume)
        }
        // A shelf can hold a volume the catalogue does not list — a different edition, say.
        let listed = Set(catalogue.map(\.bookID))
        entries += books
            .filter { book in book.hardcover.map { !listed.contains($0.id) } ?? true }
            .map(Volume.owned)
        return entries.sorted { $0.sortKey < $1.sortKey }
    }

    /// How many volumes Hardcover lists, when it lists any.
    @MainActor
    var catalogueCount: Int? {
        guard let seriesID else { return nil }
        let count = SeriesCatalog.volumes(for: seriesID).count
        return count > 0 ? count : nil
    }

    /// Resolves every collection against the (already filtered and sorted) library. The shelf
    /// itself keeps every book: a collection is another way in, not a place a book moves to.
    /// Collections the filter emptied are dropped unless nothing is filtered, so an empty
    /// hand-made collection still has somewhere to be seen.
    static func build(
        collections: [CollectionModel],
        audiobooks: [AudiobookModel],
        keepEmpty: Bool
    ) -> [CollectionGroup] {
        let byID = Dictionary(audiobooks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var groups: [CollectionGroup] = []
        for collection in collections {
            let books = sorted(collection.bookIDs.compactMap { byID[$0] }, by: collection.sort)
            if !books.isEmpty || keepEmpty {
                groups.append(CollectionGroup(collection: collection, books: books))
            }
        }
        // Collections with something in progress first, then alphabetically, so the shelf opens
        // on what is actually being listened to.
        groups.sort { lhs, rhs in
            guard lhs.isInProgress == rhs.isInProgress else { return lhs.isInProgress }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return groups
    }

    /// In progress first, then most recently played: the Library's Collections strip and the
    /// Collections screen's "Recent" sort.
    static func byRecent(_ lhs: CollectionGroup, _ rhs: CollectionGroup) -> Bool {
        guard lhs.isInProgress == rhs.isInProgress else { return lhs.isInProgress }
        guard lhs.lastPlayed == rhs.lastPlayed else { return lhs.lastPlayed > rhs.lastPlayed }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    /// `bookIDs` order for manual; otherwise the chosen key, ties broken by title.
    static func sorted(_ books: [AudiobookModel], by sort: CollectionSort) -> [AudiobookModel] {
        switch sort {
        case .manual:
            return books
        case .seriesPosition:
            return books.sorted(by: inReadingOrder)
        case .title:
            return books.sorted(by: byTitle)
        case .author:
            return books.sorted { lhs, rhs in
                let names = (lhs.author ?? "").localizedStandardCompare(rhs.author ?? "")
                return names == .orderedSame ? byTitle(lhs, rhs) : names == .orderedAscending
            }
        case .dateAdded:
            return books.sorted { lhs, rhs in
                lhs.dateAdded == rhs.dateAdded ? byTitle(lhs, rhs) : lhs.dateAdded < rhs.dateAdded
            }
        case .releaseDate:
            // Oldest first; books Hardcover has no date for go last, by title.
            return books.sorted { lhs, rhs in
                switch (lhs.hardcover?.releaseDate, rhs.hardcover?.releaseDate) {
                case let (left?, right?) where left != right: return left < right
                case (nil, .some): return false
                case (.some, nil): return true
                default: return byTitle(lhs, rhs)
                }
            }
        }
    }

    private static func byTitle(_ lhs: AudiobookModel, _ rhs: AudiobookModel) -> Bool {
        (lhs.title ?? "").localizedStandardCompare(rhs.title ?? "") == .orderedAscending
    }

    /// Volume order, falling back to title for the books Hardcover has no position for.
    static func inReadingOrder(_ lhs: AudiobookModel, _ rhs: AudiobookModel) -> Bool {
        switch (lhs.hardcover?.seriesPosition, rhs.hardcover?.seriesPosition) {
        case let (left?, right?) where left != right:
            return left < right
        case (nil, .some):
            return false
        case (.some, nil):
            return true
        default:
            return (lhs.title ?? "").localizedStandardCompare(rhs.title ?? "") == .orderedAscending
        }
    }
}

extension CollectionGroup {
    /// "3 volumes" or "3 of 6" for a series, "3 books" for a hand-made collection.
    @MainActor
    var countLabel: String {
        if let total = serverSeries?.books?.count, total > books.count {
            return String(
                format: NSLocalizedString("%d of %d", comment: "Owned volumes out of the whole series"),
                books.count,
                total
            )
        }
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
