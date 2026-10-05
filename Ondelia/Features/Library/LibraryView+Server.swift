import SwiftUI

// MARK: - Server audiobooks beside the Library (ADR 0002)
extension LibraryView {
    /// The Library's books, minus streamed ones while the server is off.
    var visibleAudiobooks: [AudiobookModel] {
        catalog.visible(audiobookManager.audiobooks, linked: AudiobookShelfService.shared.libraryBooks)
    }

    /// Server audiobooks not in the Library, as the filter lets them through: they have never
    /// been played, so they count as not started. None while selecting, which acts on books.
    var shelfServerItems: [AudiobookShelfAPI.Item] {
        guard !selecting, filterOption == .all || filterOption == .notStarted else { return [] }
        return catalog.unjoined(linked: AudiobookShelfService.shared.libraryBooks, sortedFor: sortOption)
    }

    /// The shelf: the Library's books with the server audiobooks woven in.
    var shelfEntries: [LibraryEntry] {
        LibraryEntry.merged(shelfBooks, shelfServerItems, by: sortOption)
    }

    /// Server collections, then server series, with no Collection of their own yet, by name:
    /// drawn from the catalogue, never stored (ADR 0002). One gets a Collection when one of its
    /// books joins the Library. The Collections screen lists them all, the filter aside.
    var serverOnlyCollections: [AudiobookShelfAPI.Series] {
        let stored = Set(audiobookManager.collections.map(\.id))
        return (catalog.collectionsByName + catalog.seriesByName)
            .filter { !stored.contains(AudiobookShelfCatalog.collectionID(for: $0)) }
    }

    /// The same, as the Library's filter lets them through: only where server audiobooks
    /// themselves are listed.
    var displayOnlyServerCollections: [AudiobookShelfAPI.Series] {
        guard !selecting, filterOption == .all || filterOption == .notStarted else { return [] }
        return serverOnlyCollections
    }

    var hasCollections: Bool {
        !collectionGroups.isEmpty || !displayOnlyServerCollections.isEmpty
    }

    /// No book at all, of the Library's or the server's: the empty state's cue.
    var isShelfEmpty: Bool {
        // Once active, a server book is either unjoined or a visible Library book: no need to
        // filter the whole catalogue to know.
        visibleAudiobooks.isEmpty && (!catalog.isActive || catalog.items.isEmpty)
    }

    /// The empty state's way to the server shelf; none while there is no shelf.
    var openServerShelf: (() -> Void)? {
        blendsServer ? nil : { source = .audiobookShelf }
    }

    /// What the catalogue depends on: the switch, and each server's sign-in, server library
    /// (which the AudiobookShelf shelf can change) and whether it is shown.
    var catalogKey: String {
        let service = AudiobookShelfService.shared
        let servers = service.accounts.map { "\($0.id):\($0.library ?? ""):\($0.showsInLibrary):\(service.token(for: $0) != nil)" }
        return "\(blendsServer) \(servers.joined(separator: ",")) \(source)"
    }

    /// "On This Device" / "AudiobookShelf", above either shelf. Gone while server audiobooks
    /// are shown beside the Library's: it is all one Library then (ADR 0002).
    var sourcePicker: some View {
        Picker(NSLocalizedString("Source", comment: "Library source picker"), selection: $source) {
            Text(NSLocalizedString("On This Device", comment: "Library source: books on this device"))
                .tag(LibrarySource.device)
            Text(verbatim: "AudiobookShelf").tag(LibrarySource.audiobookShelf)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, isWide ? 24 : 16)
        .padding(.vertical, 8)
        .onChange(of: source) { withHapticFeedback {} }
    }

    /// Shown while the server's audiobooks are expected and it does not answer. Tapping asks
    /// again.
    @ViewBuilder
    var serverUnreachableButton: some View {
        if catalog.isUnreachable {
            Button {
                Task { await catalog.refresh(force: true) }
            } label: {
                Image(systemName: "icloud.slash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(NSLocalizedString("Server unreachable", comment: "AudiobookShelf server did not answer"))
            .accessibilityHint(NSLocalizedString("Tries again", comment: "Retry reaching the AudiobookShelf server"))
        }
    }

    @ViewBuilder
    func listRow(_ entry: LibraryEntry) -> some View {
        switch entry {
        case .book(let book):
            libraryRow(audiobook: book)
        case .server(let item):
            AudiobookShelfBookRow(item: item)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    @ViewBuilder
    func gridCell(_ entry: LibraryEntry) -> some View {
        switch entry {
        case .book(let audiobook):
            AudiobookGridItemView(audiobook: audiobook, columns: gridColumns) { tapBook(audiobook) }
                .overlay(alignment: .topTrailing) { selectionBadge(for: audiobook) }
                .accessibilityIdentifier(AccessibilityIdentifiers.Library.audiobookCell)
                .contextMenu {
                    BookActionsMenu(audiobook: audiobook, actions: bookActions)
                }
        case .server(let item):
            AudiobookShelfBookTile(item: item, columns: gridColumns)
        }
    }
}
