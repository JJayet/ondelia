import Foundation

/// Books that Hardcover puts in the same series, in reading order.
///
/// One volume is still a series: the shelf says which series the book belongs to and where it
/// sits in it, which is the whole point of asking Hardcover.
struct SeriesGroup: Identifiable {
    let name: String
    let books: [AudiobookModel]

    var id: String { name }

    var totalDuration: TimeInterval {
        books.reduce(0) { $0 + $1.duration }
    }

    /// Progress across the whole series, weighted by length — so a finished short volume does
    /// not read as more progress than half of a long one.
    var progressFraction: Double {
        let total = totalDuration
        guard total > 0 else { return 0 }
        return books.reduce(0) { $0 + $1.currentPosition } / total
    }

    /// The volume being listened to, if any: the first unfinished book with progress, else the
    /// first unfinished one.
    var currentBook: AudiobookModel? {
        books.first { $0.currentPosition > 0 && !$0.isFinished } ?? books.first { !$0.isFinished }
    }

    /// Hardcover's id for this series, taken from whichever volume is linked.
    var seriesID: Int? {
        books.compactMap { $0.hardcover?.seriesID }.first
    }

    /// One entry in the series as the card lists it.
    enum Volume: Identifiable {
        /// A volume in the library.
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

    /// Every volume Hardcover lists for this series, with the ones on the shelf resolved to the
    /// books themselves. Falls back to just the owned books when the catalogue has not been
    /// fetched — the card then reads exactly as it did before.
    @MainActor
    var volumes: [Volume] {
        guard let seriesID else { return books.map(Volume.owned) }
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

    /// Splits a library into its series and everything else.
    static func group(_ audiobooks: [AudiobookModel]) -> (series: [SeriesGroup], standalone: [AudiobookModel]) {
        var byName: [String: [AudiobookModel]] = [:]
        var standalone: [AudiobookModel] = []

        for audiobook in audiobooks {
            if let name = audiobook.hardcover?.seriesName, !name.isEmpty {
                byName[name, default: []].append(audiobook)
            } else {
                standalone.append(audiobook)
            }
        }

        var series = byName.map { SeriesGroup(name: $0.key, books: $0.value.sorted(by: inReadingOrder)) }

        // Series with something in progress first, then alphabetically, so the shelf opens on
        // what is actually being listened to.
        series.sort { lhs, rhs in
            let left = lhs.progressFraction > 0 && lhs.progressFraction < 1
            let right = rhs.progressFraction > 0 && rhs.progressFraction < 1
            guard left == right else { return left }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return (series, standalone)
    }

    /// Volume order, falling back to title for the books Hardcover has no position for.
    private static func inReadingOrder(_ lhs: AudiobookModel, _ rhs: AudiobookModel) -> Bool {
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
