import SwiftUI

// MARK: - Regular width (iPad landscape, Mac)
//
// The design's landscape shelf: collections as compact tiles on one scrolling row instead of
// full-width bands, so the grid gets the room; and a table mode for big libraries.
extension LibraryView {
    var isWide: Bool { horizontalSizeClass == .regular }

    /// Title, count and the toolbar's buttons on one row, in place of the navigation bar.
    @ViewBuilder
    var wideHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(screenTitle)
                    .font(.system(size: 34, weight: .bold))
                Text(String(
                    format: NSLocalizedString("%d books · %d on this device", comment: "Wide library subtitle"),
                    shelfBooks.count,
                    shelfBooks.filter { audiobookManager.hasFile($0) }.count
                ))
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if selecting {
                Button(NSLocalizedString("Cancel", comment: "Cancel button")) {
                    withHapticFeedback { endSelecting() }
                }
                .buttonStyle(.plain)
                .glassPill(height: 34)

                Menu { bulkMenuItems } label: {
                    Text(String(
                        format: NSLocalizedString("%d selected", comment: "Selection count in the library toolbar"),
                        selectedIDs.count
                    ))
                    .glassPill(height: 34, tinted: true)
                }
                .buttonStyle(.plain)
            } else {
                if !showsServer {
                    Button(NSLocalizedString("Select", comment: "Enter library selection mode")) {
                        withHapticFeedback { selecting = true }
                    }
                    .buttonStyle(.plain)
                    .disabled(shelfBooks.isEmpty)
                    .glassPill(height: 34)
                }

                serverUnreachableButton
                    .buttonStyle(.plain)
                    .frame(width: 34, height: 34)
                    .glassEffect(.regular, in: Circle())

                ImportMenu {
                    showingImporter = true
                } onAudiobookShelf: {
                    source = .audiobookShelf
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 34, height: 34)
                        .glassEffect(.regular, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("Import Audiobook", comment: "Import button accessibility label"))
                .accessibilityIdentifier(AccessibilityIdentifiers.Library.importButton)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    var tableModeContent: some View {
        VStack(spacing: 12) {
            LibraryHeaderView(
                viewMode: $viewMode,
                sortOption: $sortOption,
                filterOption: $filterOption,
                gridColumns: $gridColumns
            )
            .padding(.horizontal)
            .padding(.top, 8)

            if isShelfEmpty && !audiobookManager.isImporting
                && AudiobookShelfService.shared.downloads.isEmpty {
                EmptyLibraryView(onImport: { showingImporter = true }, onAudiobookShelf: openServerShelf)
                    .padding(.horizontal)
                Spacer()
            } else {
                // The list and grid show these rows too; the table has no row slot for them.
                if !AudiobookShelfService.shared.downloads.isEmpty {
                    DownloadingIndicatorView()
                        .padding(.horizontal)
                }
                if audiobookManager.isImporting {
                    ImportingIndicatorView(manager: audiobookManager)
                        .padding(.horizontal)
                }

                LibraryTableView(
                    groups: collectionGroups,
                    uncollected: uncollectedBooks,
                    server: shelfServerItems,
                    serverSeries: displayOnlyServerCollections,
                    onOpenBook: tapBook,
                    onOpenCollection: { collectionForDetail = $0.collection },
                    onOpenServer: { AudiobookShelfService.shared.play($0, local: nil) { playAndPresent($0) } }
                )
            }
        }
    }

    /// The shelf minus every book a collection already lists.
    var uncollectedBooks: [AudiobookModel] {
        let inCollections = Set(collectionGroups.flatMap { $0.books.map(\.id) })
        return shelfBooks.filter { !inCollections.contains($0.id) }
    }
}
