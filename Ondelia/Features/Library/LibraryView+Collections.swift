import SwiftUI

// MARK: - Collections on the shelf
extension LibraryView {
    func collectionCard(_ group: CollectionGroup) -> some View {
        CollectionCardView(group: group) { collectionForDetail = group.collection }
            .contextMenu { collectionMenu(group) }
    }

    /// A Collection's long-press menu: download what is not on this device, rename, and
    /// remove it. A server series or server collection is hidden rather than deleted, which is
    /// what deleting it does anyway (`deleteCollection`).
    @ViewBuilder
    func collectionMenu(_ group: CollectionGroup) -> some View {
        let service = AudiobookShelfService.shared
        let streamed = group.books.filter(service.canStream)
        if let serverGroup = group.serverSeries {
            Button {
                withHapticFeedback(.medium) {}
                Task { await service.downloadAll(.series(serverGroup), library: "") }
            } label: {
                Label(NSLocalizedString("Download All", comment: "AudiobookShelf: download every book of a series or author"), systemImage: "arrow.down.circle")
            }
        } else if !streamed.isEmpty {
            Button {
                withHapticFeedback(.medium) {}
                streamed.forEach(service.download)
            } label: {
                Label(NSLocalizedString("Download All", comment: "AudiobookShelf: download every book of a series or author"), systemImage: "arrow.down.circle")
            }
        }
        Button {
            collectionToRename = group.collection
            newCollectionName = group.collection.name
            activeAlert = .renameCollection
        } label: {
            Label(NSLocalizedString("Rename", comment: "Rename button"), systemImage: "pencil")
        }
        Divider()
        Button(role: .destructive) {
            withHapticFeedback { audiobookManager.deleteCollection(group.collection) }
        } label: {
            if group.serverSeries != nil {
                Label(NSLocalizedString("Hide", comment: "Hide a server audiobook, series or author"), systemImage: "eye.slash")
            } else {
                Label(NSLocalizedString("Delete Collection", comment: "Delete a collection, keeping its books"), systemImage: "trash")
            }
        }
        .tint(.red)
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
