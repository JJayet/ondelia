import Foundation
import SwiftData

/// Offered when a book turns out to belong to a Hardcover series and series are not grouped
/// automatically: "Create the collection?"
struct CollectionPrompt: Identifiable {
    let id = UUID()
    let seriesID: Int
    let name: String
    let bookIDs: [UUID]
}

// MARK: - Collections
extension AudiobookManager {
    /// Settings key: Hardcover series become collections on their own (default on).
    static let autoSeriesCollectionsKey = "library.autoSeriesCollections"
    /// Series the listener said no to, or deleted: never offered or recreated again.
    private static let declinedSeriesKey = "library.declinedSeriesCollections"

    static var autoSeriesCollections: Bool {
        UserDefaults.standard.object(forKey: autoSeriesCollectionsKey) as? Bool ?? true
    }

    private var declinedSeries: Set<Int> {
        get { Set(UserDefaults.standard.array(forKey: Self.declinedSeriesKey) as? [Int] ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.declinedSeriesKey) }
    }

    func fetchCollections() {
        let descriptor = FetchDescriptor<CollectionModel>(sortBy: [SortDescriptor(\.dateCreated)])
        collections = (try? swiftDataController.context.fetch(descriptor)) ?? []
    }

    /// Makes the series collections agree with what Hardcover says about the library. Called
    /// after every library fetch and after every series lookup; idempotent and cheap.
    ///
    /// Only ever adds. iCloud brings another device's records in batches, in no set order: a
    /// collection can land before its books, and this runs after every batch. Deleting a
    /// collection, or dropping a member, that looked bookless at that moment deleted it — and
    /// the listener's order and chaining with it — on every device. A book leaves its series
    /// collection when it is deleted or its series changes here (`leaveSeriesCollections`).
    ///
    /// With automatic grouping off, a series with no collection yet is offered once through
    /// `collectionPrompt` instead of being created.
    func reconcileSeriesCollections() {
        guard swiftDataController.isLoaded else { return }
        mergeDuplicateSeriesCollections()
        var bySeries: [Int: (name: String, books: [AudiobookModel])] = [:]
        for book in audiobooks {
            guard let link = book.hardcover, let seriesID = link.seriesID,
                  let name = link.seriesName, !name.isEmpty else { continue }
            bySeries[seriesID, default: (name, [])].books.append(book)
        }

        var changed = false
        let declined = declinedSeries
        for (seriesID, series) in bySeries {
            let ordered = series.books.sorted(by: CollectionGroup.inReadingOrder).map(\.id)
            if let existing = collections.first(where: { $0.hardcoverSeriesID == seriesID }) {
                // A series collection follows Hardcover for its name and its members. The order
                // is the listener's: a volume that is new to it goes on the end, and the sort
                // mode decides how the card shows it.
                if existing.name != series.name { existing.name = series.name; changed = true }
                let added = ordered.filter { !existing.bookIDs.contains($0) }
                if !added.isEmpty { existing.bookIDs += added; changed = true }
            } else if declined.contains(seriesID) {
                continue
            } else if Self.autoSeriesCollections {
                swiftDataController.context.insert(
                    CollectionModel(name: series.name, hardcoverSeriesID: seriesID, bookIDs: ordered, sort: .seriesPosition)
                )
                changed = true
            } else if collectionPrompt == nil {
                collectionPrompt = CollectionPrompt(seriesID: seriesID, name: series.name, bookIDs: ordered)
            }
        }
        if changed {
            swiftDataController.save()
            fetchCollections()
        }
    }

    /// The answer to a `CollectionPrompt`.
    func respondToCollectionPrompt(_ prompt: CollectionPrompt, create: Bool) {
        collectionPrompt = nil
        if create {
            swiftDataController.context.insert(
                CollectionModel(name: prompt.name, hardcoverSeriesID: prompt.seriesID, bookIDs: prompt.bookIDs, sort: .seriesPosition)
            )
            swiftDataController.save()
            fetchCollections()
        } else {
            declinedSeries.insert(prompt.seriesID)
        }
    }

    @discardableResult
    func createCollection(name: String, books: [AudiobookModel]) -> CollectionModel? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let collection = CollectionModel(name: trimmed, bookIDs: books.map(\.id))
        swiftDataController.context.insert(collection)
        swiftDataController.save()
        fetchCollections()
        return collection
    }

    func add(_ books: [AudiobookModel], to collection: CollectionModel) {
        let present = Set(collection.bookIDs)
        collection.bookIDs += books.map(\.id).filter { !present.contains($0) }
        swiftDataController.save()
        fetchCollections()
    }

    func remove(_ book: AudiobookModel, from collection: CollectionModel) {
        collection.bookIDs.removeAll { $0 == book.id }
        swiftDataController.save()
        fetchCollections()
    }

    func setSort(_ sort: CollectionSort, for collection: CollectionModel) {
        // Going manual keeps what the listener was looking at, so the drag starts from there.
        if sort == .manual, collection.sort != .manual {
            let byID = Dictionary(audiobooks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let shown = CollectionGroup.sorted(collection.bookIDs.compactMap { byID[$0] }, by: collection.sort).map(\.id)
            collection.bookIDs = shown + collection.bookIDs.filter { !shown.contains($0) }
        }
        collection.sort = sort
        swiftDataController.save()
        fetchCollections()
    }

    /// Manual order: puts `book` where `target` is (dropping onto a row), or at the end when
    /// `target` is nil. Switches the collection to manual if it was not.
    func move(_ book: AudiobookModel, before target: AudiobookModel?, in collection: CollectionModel) {
        guard book.id != target?.id else { return }
        if collection.sort != .manual { setSort(.manual, for: collection) }
        var ids = collection.bookIDs.filter { $0 != book.id }
        if let target, let index = ids.firstIndex(of: target.id) {
            ids.insert(book.id, at: index)
        } else {
            ids.append(book.id)
        }
        collection.bookIDs = ids
        swiftDataController.save()
        fetchCollections()
    }

    /// Manual order: one step up (`-1`) or down (`+1`) in the list as shown.
    func move(_ book: AudiobookModel, by offset: Int, in collection: CollectionModel) {
        if collection.sort != .manual { setSort(.manual, for: collection) }
        guard let index = collection.bookIDs.firstIndex(of: book.id) else { return }
        let destination = index + offset
        guard collection.bookIDs.indices.contains(destination) else { return }
        collection.bookIDs.swapAt(index, destination)
        swiftDataController.save()
        fetchCollections()
    }

    func setAutoContinue(_ on: Bool, for collection: CollectionModel) {
        collection.autoContinue = on
        swiftDataController.save()
        fetchCollections()
    }

    /// The books of a collection in the order its card shows them.
    func orderedBooks(in collection: CollectionModel) -> [AudiobookModel] {
        let byID = Dictionary(audiobooks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return CollectionGroup.sorted(collection.bookIDs.compactMap { byID[$0] }, by: collection.sort)
    }

    /// What plays after `book` ends: the next unfinished, playable book of the first collection
    /// that holds it and chains its books — in a server series, possibly one that has not
    /// joined yet. Nil when nothing does.
    func nextEntry(after book: AudiobookModel) -> LibraryEntry? {
        for collection in collections where collection.autoContinue && collection.bookIDs.contains(book.id) {
            if AudiobookShelfCatalog.shared.seriesByCollection[collection.id] != nil {
                if let next = nextServerSeriesEntry(after: book, in: collection) { return next }
                continue
            }
            let ordered = orderedBooks(in: collection)
            guard let index = ordered.firstIndex(where: { $0.id == book.id }) else { continue }
            if let next = ordered.dropFirst(index + 1).first(where: { !$0.isFinished && isPlayable($0) }) {
                return .book(next)
            }
        }
        return nil
    }

    func renameCollection(_ collection: CollectionModel, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        collection.name = trimmed
        swiftDataController.save()
        fetchCollections()
    }

    /// The books stay. A series collection is also remembered as declined, and a server series
    /// one hidden, otherwise the next reconcile would put it straight back.
    func deleteCollection(_ collection: CollectionModel) {
        let catalog = AudiobookShelfCatalog.shared
        if let seriesID = collection.hardcoverSeriesID { declinedSeries.insert(seriesID) }
        else if let series = catalog.seriesByCollection[collection.id], let serverID = catalog.serverID {
            hideServerGroup(series, on: serverID)
            return
        }
        // Any other Collection may be a server series one; remembering a hand-made one's id
        // costs nothing, since no series will ever derive it.
        else { declinedServerSeries.insert(collection.id.uuidString) }
        swiftDataController.context.delete(collection)
        swiftDataController.save()
        fetchCollections()
    }

    /// Called when a book leaves the library, so no collection keeps pointing at it. A series
    /// collection goes with its last member: the listener removed it here, so this is not a
    /// sync batch arriving half done (see the reconcile functions). Not declined: the next
    /// book of the series brings it straight back.
    func removeFromAllCollections(bookID: UUID) {
        let serverSeries = AudiobookShelfCatalog.shared.seriesByCollection
        for collection in collections where collection.bookIDs.contains(bookID) {
            collection.bookIDs.removeAll { $0 == bookID }
            if collection.bookIDs.isEmpty, collection.isSeries || serverSeries[collection.id] != nil {
                swiftDataController.context.delete(collection)
            }
        }
    }

    /// Takes `book` out of the Hardcover series collections it no longer belongs to: unlinked
    /// from Hardcover, or now in another series. Called where that change is made on this
    /// device, never from a reconcile (see `reconcileSeriesCollections`).
    func leaveSeriesCollections(_ book: AudiobookModel) {
        let seriesID = book.hardcover?.seriesID
        var changed = false
        for collection in collections where collection.isSeries
            && collection.hardcoverSeriesID != seriesID && collection.bookIDs.contains(book.id) {
            collection.bookIDs.removeAll { $0 == book.id }
            if collection.bookIDs.isEmpty { swiftDataController.context.delete(collection) }
            changed = true
        }
        if changed {
            swiftDataController.save()
            fetchCollections()
        }
    }
}
