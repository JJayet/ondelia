import SwiftUI

// MARK: - Collections on the shelf
extension LibraryView {
    /// The strip holds this many: the rest wait behind See All.
    static let stripLimit = 8

    /// One row of Collection tiles, in progress first, then recently played, and See All to the
    /// Collections screen. Server collections and series with no Collection yet fill what room
    /// is left: they have never been played.
    var collectionsStrip: some View {
        let groups = collectionGroups.sorted(by: CollectionGroup.byRecent).prefix(Self.stripLimit)
        let server = displayOnlyServerCollections.prefix(Self.stripLimit - groups.count)
        let tileWidth: CGFloat = isWide ? 200 : 150
        let padding: CGFloat = isWide ? 24 : 16
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(NSLocalizedString("Collections", comment: "Section title for collections"))
                    .font(.system(size: 19, weight: .bold))
                Text(verbatim: "\(collectionGroups.count + displayOnlyServerCollections.count)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(NSLocalizedString("See All", comment: "Library: open the Collections screen")) {
                    withHapticFeedback { showsAllCollections = true }
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.tint)
                .buttonStyle(.plain)
                .accessibilityIdentifier(AccessibilityIdentifiers.Library.seeAllCollections)
            }
            .padding(.horizontal, padding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 11) {
                    ForEach(groups) { group in
                        CollectionTileView(group: group, onOpen: { collectionForDetail = group.collection }, width: tileWidth)
                            .contextMenu { collectionMenu(group) }
                    }
                    ForEach(server) { AudiobookShelfSeriesTile(series: $0, width: tileWidth) }
                }
                .padding(.horizontal, padding)
            }
        }
    }

    /// The Collections screen: every Collection, unfiltered, and every server collection and
    /// series with none yet.
    var allCollections: some View {
        CollectionsView(
            groups: CollectionGroup.build(
                collections: audiobookManager.collections,
                audiobooks: visibleAudiobooks,
                keepEmpty: true
            ),
            serverOnly: serverOnlyCollections,
            onOpen: { collectionForDetail = $0.collection },
            menu: collectionMenu
        )
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
