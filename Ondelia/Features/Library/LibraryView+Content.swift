import SwiftUI
import TipKit

// MARK: - List / Grid content
extension LibraryView {
    /// The shelf lists every book, whether or not a collection card also shows it.
    var shelfBooks: [AudiobookModel] {
        filteredAudiobooks
    }

    /// Books stacked to play next, in queue order.
    var queuedBooks: [AudiobookModel] {
        PlayQueue.shared.books(in: visibleAudiobooks)
    }

    var gridSpacing: CGFloat { gridColumns >= 4 ? 10 : 16 }

    // Extracted to help the type-checker
    @ViewBuilder
    var listModeContent: some View {
        List {
            // Continue Reading Section
            if !continueReading.isEmpty {
                ContinueReadingSection(entries: continueReading, headerPadding: 0, rowPadding: 4, wide: isWide) { playAndPresent($0) }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            // Play queue
            if !queuedBooks.isEmpty {
                QueueSectionView(books: queuedBooks, horizontalPadding: 0, onSelect: playQueued)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            // Collections: Hardcover series and hand-made ones, then the server series that
            // are not one yet. Wide: one row of tiles.
            if isWide, hasCollections {
                collectionsRow
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } else {
                if hasCollections {
                    SectionLabel(NSLocalizedString("Collections", comment: "Section title for collections"))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 2, trailing: 16))
                }
                ForEach(collectionGroups) { group in
                    collectionCard(group)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
                serverSeriesToggle
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                ForEach(shownServerSeries) { series in
                    AudiobookShelfSeriesCard(series: series)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }

            if !isShelfEmpty {
                SectionLabel(NSLocalizedString("Library", comment: "Library navigation title"))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 2, trailing: 16))
            }

            TipView(LongPressBookTip())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

            // Header with filters
            LibraryHeaderView(
                viewMode: $viewMode,
                sortOption: $sortOption,
                filterOption: $filterOption,
                gridColumns: $gridColumns
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            // Library Items
            if isShelfEmpty && !audiobookManager.isImporting
                && AudiobookShelfService.shared.downloads.isEmpty {
                EmptyLibraryView(onImport: { showingImporter = true }, onAudiobookShelf: openServerShelf)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 40, leading: 0, bottom: 40, trailing: 0))
            } else {
                if !AudiobookShelfService.shared.downloads.isEmpty {
                    DownloadingIndicatorView()
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }

                if audiobookManager.isImporting {
                    ImportingIndicatorView(manager: audiobookManager)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }

                ForEach(shelfEntries, content: listRow)
            }
        }
        .listStyle(PlainListStyle())
        .scrollContentBackground(.hidden)
    }

    // Grid mode - use ScrollView
    @ViewBuilder
    var gridModeContent: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                // Continue Reading Section
                if !continueReading.isEmpty {
                    ContinueReadingSection(entries: continueReading, headerPadding: nil, rowPadding: nil, wide: isWide) { playAndPresent($0) }
                }

                // Play queue
                if !queuedBooks.isEmpty {
                    QueueSectionView(books: queuedBooks, horizontalPadding: nil, onSelect: playQueued)
                }

                // Collections: Hardcover series and hand-made ones, then the server series that
                // are not one yet. Wide: one row of tiles. Lazy: a server can have hundreds.
                if isWide, hasCollections {
                    collectionsRow.padding(.horizontal)
                } else if hasCollections {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        SectionLabel(NSLocalizedString("Collections", comment: "Section title for collections"))
                        ForEach(collectionGroups) { group in
                            collectionCard(group)
                        }
                        serverSeriesToggle
                        ForEach(shownServerSeries) { AudiobookShelfSeriesCard(series: $0) }
                    }
                    .padding(.horizontal)
                }

                // Main Library Section
                VStack(alignment: .leading, spacing: 16) {
                    if !isShelfEmpty {
                        SectionLabel(NSLocalizedString("Library", comment: "Library navigation title"))
                            .padding(.horizontal)
                    }

                    TipView(LongPressBookTip())
                        .padding(.horizontal)

                    // Header with filters
                    LibraryHeaderView(
                        viewMode: $viewMode,
                        sortOption: $sortOption,
                        filterOption: $filterOption,
                        gridColumns: $gridColumns
                    )
                    .padding(.horizontal)

                    // Content
                    if isShelfEmpty && !audiobookManager.isImporting
                        && AudiobookShelfService.shared.downloads.isEmpty {
                        EmptyLibraryView(onImport: { showingImporter = true }, onAudiobookShelf: openServerShelf)
                        .padding(.horizontal)
                    } else {
                        VStack(spacing: 16) {
                            if !AudiobookShelfService.shared.downloads.isEmpty {
                                DownloadingIndicatorView()
                                    .padding(.horizontal)
                            }

                            if audiobookManager.isImporting {
                                ImportingIndicatorView(manager: audiobookManager)
                                    .padding(.horizontal)
                            }

                            // The preference sets the density at phone width; a wider window
                            // (iPad, Split View, iPhone Duo open) keeps that cover size and fits
                            // more columns, so the grid follows the space rather than the idiom.
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 300 / CGFloat(gridColumns)), spacing: gridSpacing)],
                                spacing: gridSpacing
                            ) {
                                ForEach(shelfEntries, content: gridCell)
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
    }
}

// MARK: - Row Builders
extension LibraryView {
    @ViewBuilder
    func libraryRow(audiobook: AudiobookModel) -> some View {
        EnhancedAudiobookRowView(
            audiobook: audiobook,
            selection: selecting ? selectedIDs.contains(audiobook.id) : nil
        ) { tapBook(audiobook) }
            .accessibilityIdentifier(AccessibilityIdentifiers.Library.audiobookCell)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            // No full swipe: the gesture used to delete the book, its progress and its
            // bookmarks with nothing to confirm and nothing to undo.
            // No swipes on the Mac at all: a trackpad swipe left the row pushed aside under
            // two tall blocks, and the right-click menu already holds every action.
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if !Self.onMac {
                    Button(NSLocalizedString("Delete", comment: "Delete button"), role: .destructive) {
                        withHapticFeedback { activeAlert = .confirmDelete(audiobook) }
                    }
                    // The app-wide accent tint wins over the destructive role's red without this.
                    .tint(.red)
                }
            }
            .swipeActions(edge: .leading) {
                if !Self.onMac {
                Button(audiobook.isFinished ? NSLocalizedString("Mark Unread", comment: "Mark as unread") : NSLocalizedString("Mark Read", comment: "Mark as read")) {
                    withHapticFeedback {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            ListenerState.shared.apply(
                                audiobook.isFinished ? .unfinish : .finish, to: audiobook, from: .listener
                            )
                        }
                    }
                }
                .tint(audiobook.isFinished ? .orange : .green)

                Button(NSLocalizedString("Rename", comment: "Rename button")) {
                    withHapticFeedback {
                        audiobookToRename = audiobook
                        newAudiobookTitle = audiobook.title ?? ""
                        activeAlert = .rename
                    }
                }
                .tint(.blue)
                }
            }
            .contextMenu {
                BookActionsMenu(audiobook: audiobook, actions: bookActions)
            }
    }

    static let onMac = ProcessInfo.processInfo.isiOSAppOnMac
}
