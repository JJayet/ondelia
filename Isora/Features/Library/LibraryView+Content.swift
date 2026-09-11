import SwiftUI

// MARK: - List / Grid content
extension LibraryView {
    /// The shelf lists every book, whether or not a collection card also shows it.
    var shelfBooks: [AudiobookModel] {
        filteredAudiobooks
    }

    /// Books stacked to play next, in queue order.
    var queuedBooks: [AudiobookModel] {
        PlayQueue.shared.books(in: audiobookManager.audiobooks)
    }

    // Extracted to help the type-checker
    @ViewBuilder
    var listModeContent: some View {
        List {
            // Continue Reading Section
            if !continueReading.isEmpty {
                ContinueReadingSection(entries: continueReading, headerPadding: 0, rowPadding: 4) { playAndPresent($0) }
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

            // Collections: Hardcover series and hand-made ones
            if !collectionGroups.isEmpty {
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

            if !audiobookManager.audiobooks.isEmpty {
                SectionLabel(NSLocalizedString("Library", comment: "Library navigation title"))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 2, trailing: 16))
            }

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
            if audiobookManager.audiobooks.isEmpty && !audiobookManager.isImporting {
                EmptyLibraryView { showingImporter = true }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 40, leading: 0, bottom: 40, trailing: 0))
            } else {
                if audiobookManager.isImporting {
                    ImportingIndicatorView(manager: audiobookManager)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }

                ForEach(shelfBooks, id: \.id, content: libraryRow)
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
                    ContinueReadingSection(entries: continueReading, headerPadding: nil, rowPadding: nil) { playAndPresent($0) }
                }

                // Play queue
                if !queuedBooks.isEmpty {
                    QueueSectionView(books: queuedBooks, horizontalPadding: nil, onSelect: playQueued)
                }

                // Collections: Hardcover series and hand-made ones
                if !collectionGroups.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(NSLocalizedString("Collections", comment: "Section title for collections"))
                        ForEach(collectionGroups) { group in
                            collectionCard(group)
                        }
                    }
                    .padding(.horizontal)
                }

                // Main Library Section
                VStack(alignment: .leading, spacing: 16) {
                    if !audiobookManager.audiobooks.isEmpty {
                        SectionLabel(NSLocalizedString("Library", comment: "Library navigation title"))
                            .padding(.horizontal)
                    }

                    // Header with filters
                    LibraryHeaderView(
                        viewMode: $viewMode,
                        sortOption: $sortOption,
                        filterOption: $filterOption,
                        gridColumns: $gridColumns
                    )
                    .padding(.horizontal)

                    // Content
                    if audiobookManager.audiobooks.isEmpty && !audiobookManager.isImporting {
                        EmptyLibraryView { showingImporter = true }
                        .padding(.horizontal)
                    } else {
                        VStack(spacing: 16) {
                            if audiobookManager.isImporting {
                                ImportingIndicatorView(manager: audiobookManager)
                                    .padding(.horizontal)
                            }

                            LazyVGrid(
                                columns: Array(
                                    repeating: GridItem(.flexible(), spacing: gridColumns >= 4 ? 10 : 16),
                                    count: gridColumns
                                ),
                                spacing: gridColumns >= 4 ? 10 : 16
                            ) {
                                ForEach(shelfBooks, id: \.id) { audiobook in
                                    AudiobookGridItemView(audiobook: audiobook, columns: gridColumns) { tapBook(audiobook) }
                                    .overlay(alignment: .topTrailing) { selectionBadge(for: audiobook) }
                                    .accessibilityIdentifier(AccessibilityIdentifiers.Library.audiobookCell)
                                    .contextMenu {
                                        BookActionsMenu(audiobook: audiobook, actions: bookActions)
                                    }
                                }
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
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(NSLocalizedString("Delete", comment: "Delete button"), role: .destructive) {
                    withHapticFeedback { activeAlert = .confirmDelete(audiobook) }
                }
                // The app-wide accent tint wins over the destructive role's red without this.
                .tint(.red)
            }
            .swipeActions(edge: .leading) {
                Button(audiobook.isFinished ? NSLocalizedString("Mark Unread", comment: "Mark as unread") : NSLocalizedString("Mark Read", comment: "Mark as read")) {
                    withHapticFeedback {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            if audiobook.isFinished {
                                audiobookManager.markAsUnread(audiobook)
                            } else {
                                audiobookManager.markAsRead(audiobook)
                            }
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
            .contextMenu {
                BookActionsMenu(audiobook: audiobook, actions: bookActions)
            }
    }
}
