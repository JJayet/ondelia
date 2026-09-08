import SwiftUI

// MARK: - Collections on the shelf
extension LibraryView {
    func collectionCard(_ group: CollectionGroup) -> some View {
        CollectionCardView(
            group: group,
            showMissing: showMissingSeriesBooks,
            bookActions: bookActions,
            onSelect: { audiobookForDetail = $0 },
            onRename: { collection in
                collectionToRename = collection
                newCollectionName = collection.name
                activeAlert = .renameCollection
            },
            onDelete: { audiobookManager.deleteCollection($0) },
            onRemoveBook: { book, collection in audiobookManager.remove(book, from: collection) },
            onSort: { sort, collection in audiobookManager.setSort(sort, for: collection) },
            onMove: { book, target, collection in audiobookManager.move(book, before: target, in: collection) },
            onMoveBy: { book, offset, collection in audiobookManager.move(book, by: offset, in: collection) }
        )
    }

    func openCollectionPicker(for books: [AudiobookModel]) {
        booksForCollectionPicker = books
        showingCollectionPicker = true
    }

    /// One alert slot: a series offer waits while another alert is up and is raised again when
    /// that one closes (see `dismissActiveAlert`).
    func offerCollectionPromptIfIdle() {
        guard let prompt = audiobookManager.collectionPrompt, activeAlert == nil else { return }
        Task { @MainActor in
            guard audiobookManager.collectionPrompt?.id == prompt.id, activeAlert == nil else { return }
            activeAlert = .createCollection(prompt)
        }
    }

    func commitCollectionRename() {
        if let collection = collectionToRename {
            audiobookManager.renameCollection(collection, to: newCollectionName)
        }
    }
}
