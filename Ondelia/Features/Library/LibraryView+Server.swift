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
        return catalog.unjoined(linked: AudiobookShelfService.shared.libraryBooks)
    }

    /// The shelf: the Library's books with the server audiobooks woven in.
    var shelfEntries: [LibraryEntry] {
        LibraryEntry.merged(shelfBooks, shelfServerItems, by: sortOption)
    }

    /// No book at all, of the Library's or the server's: the empty state's cue.
    var isShelfEmpty: Bool {
        visibleAudiobooks.isEmpty && catalog.unjoined(linked: AudiobookShelfService.shared.libraryBooks).isEmpty
    }

    /// What the catalogue depends on: the switch, the account, and the server library, which
    /// the AudiobookShelf shelf can change.
    var catalogKey: String {
        let service = AudiobookShelfService.shared
        return "\(blendsServer) \(service.server?.absoluteString ?? "") \(service.token != nil) \(source)"
    }

    /// "On This Device" / "AudiobookShelf", above either shelf. "Library" while server
    /// audiobooks are shown beside it, since it no longer means this device only.
    var sourcePicker: some View {
        Picker(NSLocalizedString("Source", comment: "Library source picker"), selection: $source) {
            Text(catalog.isActive
                ? NSLocalizedString("Library", comment: "Library navigation title")
                : NSLocalizedString("On This Device", comment: "Library source: books on this device"))
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
                Task { await catalog.refresh() }
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
