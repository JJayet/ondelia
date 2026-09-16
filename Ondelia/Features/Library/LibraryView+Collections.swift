import SwiftUI

// MARK: - Collections on the shelf
extension LibraryView {
    func collectionCard(_ group: CollectionGroup) -> some View {
        CollectionCardView(group: group) { collectionForDetail = group.collection }
    }

    func collectionDetail(_ collection: CollectionModel) -> some View {
        CollectionDetailView(
            collection: collection,
            bookActions: bookActions,
            onSelectBook: { audiobookForDetail = $0 },
            onRename: { collection in
                collectionToRename = collection
                newCollectionName = collection.name
                activeAlert = .renameCollection
            },
            onDelete: { collection in
                collectionForDetail = nil
                audiobookManager.deleteCollection(collection)
            }
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
