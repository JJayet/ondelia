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
    /// Only ever adds. iCloud brings another device's records in batches, in no set order: a
    /// Collection can land before the server links of its books, and this runs after every
    /// batch. Deleting a Collection, or dropping a member, that looked unlinked at that moment
    /// deleted it on every device. A member goes when its book leaves the Library, and the
    /// Collection with its last member (`removeFromAllCollections`).
    func reconcileServerSeriesCollections() {
        let catalog = AudiobookShelfCatalog.shared
        guard swiftDataController.isLoaded, catalog.isActive, catalog.status == .ready else { return }
        mergeDuplicateSeriesCollections()
        let linked = AudiobookShelfService.shared.libraryBooks
        migrateDeclinedServerSeries()
        let declined = declinedServerSeries
        let hidden = AudiobookShelfHidden.shared
        var changed = false
        for series in catalog.groups where !hidden.isHidden(series.hiddenKind, series.id, on: catalog.serverID) {
            let id = AudiobookShelfCatalog.collectionID(for: series)
            let members = (series.books ?? []).compactMap { linked[$0.id]?.id }
            guard !members.isEmpty else { continue }
            if let existing = collections.first(where: { $0.id == id }) {
                if existing.name != series.name { existing.name = series.name; changed = true }
                // The listener's order, new volumes on the end.
                let added = members.filter { !existing.bookIDs.contains($0) }
                if !added.isEmpty { existing.bookIDs += added; changed = true }
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

    /// Server series Collections deleted before hiding existed become hidden series, once the
    /// catalogue says which series each id stands for.
    private func migrateDeclinedServerSeries() {
        let catalog = AudiobookShelfCatalog.shared
        guard let serverID = catalog.serverID else { return }
        var declined = declinedServerSeries
        guard !declined.isEmpty else { return }
        for series in catalog.series {
            let id = AudiobookShelfCatalog.collectionID(forSeries: series.id).uuidString
            guard declined.remove(id) != nil else { continue }
            AudiobookShelfHidden.shared.hide(.series, series.id, name: series.name, on: serverID)
        }
        declinedServerSeries = declined
    }

    /// Hides a server series or server collection: its Collection, if the Library made one,
    /// goes too. Its books stay.
    func hideServerGroup(_ group: AudiobookShelfAPI.Series, on serverID: String) {
        AudiobookShelfHidden.shared.hide(group.hiddenKind, group.id, name: group.name, on: serverID)
        let id = AudiobookShelfCatalog.collectionID(for: group)
        if let collection = collections.first(where: { $0.id == id }) {
            swiftDataController.context.delete(collection)
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
