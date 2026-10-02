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

    /// Server series with no Collection of their own yet, by name: drawn from the catalogue
    /// after the Collections, never stored (ADR 0002). One gets a Collection when one of its
    /// books joins the Library. Only where server audiobooks themselves are listed.
    var displayOnlySeries: [AudiobookShelfAPI.Series] {
        guard !selecting, filterOption == .all || filterOption == .notStarted else { return [] }
        let stored = Set(audiobookManager.collections.map(\.id))
        return catalog.seriesByName.filter { !stored.contains(AudiobookShelfCatalog.collectionID(forSeries: $0.id)) }
    }

    /// The series behind the folded "Server series" row, once it is opened.
    var shownServerSeries: [AudiobookShelfAPI.Series] { showsServerSeries ? displayOnlySeries : [] }

    /// Folds the server series into one row: a server can have hundreds, which would push the
    /// Library's own books a long scroll down. Tapping opens or closes it.
    @ViewBuilder
    var serverSeriesToggle: some View {
        if !displayOnlySeries.isEmpty {
            Button {
                withHapticFeedback {
                    withAnimation(.easeInOut(duration: 0.25)) { showsServerSeries.toggle() }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tint)
                    Text(NSLocalizedString("Server series", comment: "Library: folded row of server series"))
                        .font(.system(size: 15, weight: .semibold))
                    Text(verbatim: "\(displayOnlySeries.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(.quaternary, in: Capsule())
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showsServerSeries ? 90 : 0))
                }
                .padding(.horizontal, 16)
                .frame(height: 46)
                .contentShape(Rectangle())
                .glassCard(cornerRadius: 18)
            }
            .buttonStyle(.plain)
            .accessibilityValue(showsServerSeries
                ? NSLocalizedString("Expanded", comment: "Accessibility: folded row is open")
                : NSLocalizedString("Collapsed", comment: "Accessibility: folded row is closed"))
        }
    }

    var hasCollections: Bool { !collectionGroups.isEmpty || !displayOnlySeries.isEmpty }

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

    /// What the catalogue depends on: the switch, the account, and the server library, which
    /// the AudiobookShelf shelf can change.
    var catalogKey: String {
        let service = AudiobookShelfService.shared
        return "\(blendsServer) \(service.server?.absoluteString ?? "") \(service.token != nil) \(source)"
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
