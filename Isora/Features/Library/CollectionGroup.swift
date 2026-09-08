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

        var id: String {
            switch self {
            case .owned(let book): return book.id.uuidString
            case .missing(let volume): return "hardcover-\(volume.bookID)"
            }
        }

        var sortKey: Double {
            switch self {
            case .owned(let book): return book.hardcover?.seriesPosition ?? .greatestFiniteMagnitude
            case .missing(let volume): return volume.position ?? .greatestFiniteMagnitude
            }
        }
    }

    /// The card's rows. A series with `showMissing` on lists Hardcover's whole catalogue, the
    /// owned volumes resolved to the books themselves; otherwise just the books, in order.
    @MainActor
    func volumes(showMissing: Bool) -> [Volume] {
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
            let books = collection.bookIDs.compactMap { byID[$0] }
            if !books.isEmpty || keepEmpty {
                groups.append(CollectionGroup(collection: collection, books: books))
            }
        }
        // Collections with something in progress first, then alphabetically, so the shelf opens
        // on what is actually being listened to.
        groups.sort { lhs, rhs in
            let left = lhs.progressFraction > 0 && lhs.progressFraction < 1
            let right = rhs.progressFraction > 0 && rhs.progressFraction < 1
            guard left == right else { return left }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return groups
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
