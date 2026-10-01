import Foundation

// MARK: - Server series as Collections (ADR 0002)
extension AudiobookManager {
    /// Server series Collections the listener deleted: never made again. Keyed by Collection id,
    /// which is derived from the series, so deleting needs no catalogue to say which series it was.
    private static let declinedServerSeriesKey = "library.declinedServerSeriesCollections"

    var declinedServerSeries: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.declinedServerSeriesKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.declinedServerSeriesKey) }
    }

    /// Makes the server series Collections agree with the server: one for every series the
    /// Library holds a book of, its Library members kept in series order. The rest of its
    /// members are not stored; `CollectionGroup` reads them from the catalogue.
    ///
    /// Only with the catalogue fetched, since that is the only time it is the whole truth. A
    /// series whose last Library book left goes; a series gone from the server keeps its
    /// Collection, as a hand-made one would be kept.
    func reconcileServerSeriesCollections() {
        let catalog = AudiobookShelfCatalog.shared
        guard swiftDataController.isLoaded, catalog.isActive, catalog.status == .ready else { return }
        mergeDuplicateSeriesCollections()
        let linked = AudiobookShelfService.shared.libraryBooks
        let declined = declinedServerSeries
        var changed = false
        for series in catalog.series {
            let id = AudiobookShelfCatalog.collectionID(forSeries: series.id)
            let members = (series.books ?? []).compactMap { linked[$0.id]?.id }
            let existing = collections.first { $0.id == id }
            if members.isEmpty {
                if let existing {
                    swiftDataController.context.delete(existing)
                    changed = true
                }
                continue
            }
            if let existing {
                if existing.name != series.name { existing.name = series.name; changed = true }
                // Same rule as a Hardcover series: the listener's order, new volumes on the end.
                let present = Set(members)
                var ids = existing.bookIDs.filter { present.contains($0) }
                ids += members.filter { !ids.contains($0) }
                if existing.bookIDs != ids { existing.bookIDs = ids; changed = true }
            } else if !declined.contains(id.uuidString) {
                swiftDataController.context.insert(CollectionModel(id: id, name: series.name, bookIDs: members))
                changed = true
            }
        }
        if changed {
            swiftDataController.save()
            fetchCollections()
        }
    }

    /// What plays after `book` ends in a server series Collection that chains its books: the
    /// next member in series order that is unfinished and can play, whether or not it has
    /// joined the Library. Nil when `collection` is not one, or nothing is left.
    func nextServerSeriesEntry(after book: AudiobookModel, in collection: CollectionModel) -> LibraryEntry? {
        guard let series = AudiobookShelfCatalog.shared.seriesByCollection[collection.id] else { return nil }
        let linked = AudiobookShelfService.shared.libraryBooks
        let books = series.books ?? []
        guard let index = books.firstIndex(where: { linked[$0.id]?.id == book.id }) else { return nil }
        for item in books.dropFirst(index + 1) {
            if let member = linked[item.id] {
                if !member.isFinished && isPlayable(member) { return .book(member) }
            } else {
                return .server(item)
            }
        }
        return nil
    }
}
