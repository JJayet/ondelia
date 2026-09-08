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
    /// With automatic grouping off, a series with no collection yet is offered once through
    /// `collectionPrompt` instead of being created.
    func reconcileSeriesCollections() {
        guard swiftDataController.isLoaded else { return }
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
                // A series collection follows Hardcover: its name and its volume order are not
                // the listener's to edit, so they are simply kept in step.
                if existing.name != series.name { existing.name = series.name; changed = true }
                if existing.bookIDs != ordered { existing.bookIDs = ordered; changed = true }
            } else if declined.contains(seriesID) {
                continue
            } else if Self.autoSeriesCollections {
                swiftDataController.context.insert(CollectionModel(name: series.name, hardcoverSeriesID: seriesID, bookIDs: ordered))
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
            swiftDataController.context.insert(CollectionModel(name: prompt.name, hardcoverSeriesID: prompt.seriesID, bookIDs: prompt.bookIDs))
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

    func renameCollection(_ collection: CollectionModel, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        collection.name = trimmed
        swiftDataController.save()
        fetchCollections()
    }

    /// The books stay. A series collection is also remembered as declined, otherwise the next
    /// reconcile would put it straight back.
    func deleteCollection(_ collection: CollectionModel) {
        if let seriesID = collection.hardcoverSeriesID { declinedSeries.insert(seriesID) }
        swiftDataController.context.delete(collection)
        swiftDataController.save()
        fetchCollections()
    }

    /// Called when a book leaves the library, so no collection keeps pointing at it.
    func removeFromAllCollections(bookID: UUID) {
        for collection in collections where collection.bookIDs.contains(bookID) {
            collection.bookIDs.removeAll { $0 == bookID }
        }
    }
}
