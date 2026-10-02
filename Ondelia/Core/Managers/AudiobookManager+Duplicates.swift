import Foundation

// MARK: - Collections made twice
extension AudiobookManager {
    /// Folds Collections that stand for the same series into one.
    ///
    /// Each device makes series Collections on its own. When a second device reconciles before
    /// iCloud has brought it the first one's, both make one, and CloudKit then holds two records
    /// for the series — with the same `hardcoverSeriesID`, or for a server series the same
    /// derived `id`. Every device keeps the same one, the oldest, so two devices folding at
    /// once agree on what stays. Returns whether anything was deleted.
    @discardableResult
    func mergeDuplicateSeriesCollections() -> Bool {
        var groups: [String: [CollectionModel]] = [:]
        for collection in collections {
            let key = collection.hardcoverSeriesID.map { "hardcover-\($0)" } ?? "id-\(collection.id.uuidString)"
            groups[key, default: []].append(collection)
        }
        var changed = false
        for duplicates in groups.values where duplicates.count > 1 {
            let ordered = duplicates.sorted(by: Self.isKeptFirst)
            let kept = ordered[0]
            for extra in ordered.dropFirst() {
                // Nothing the listener did on either copy is lost: books added by hand, and the
                // chaining switch, carry over.
                kept.bookIDs += extra.bookIDs.filter { !kept.bookIDs.contains($0) }
                if extra.autoContinue { kept.autoContinue = true }
                swiftDataController.context.delete(extra)
            }
            changed = true
        }
        if changed {
            swiftDataController.save()
            fetchCollections()
        }
        return changed
    }

    /// Oldest first: `dateCreated` travels with the record, so every device ranks the copies
    /// alike. Two copies made in the same instant are equally good to keep.
    static func isKeptFirst(_ lhs: CollectionModel, _ rhs: CollectionModel) -> Bool {
        lhs.dateCreated < rhs.dateCreated
    }
}
