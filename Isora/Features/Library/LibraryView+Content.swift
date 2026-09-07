import SwiftUI

// MARK: - List / Grid content
extension LibraryView {
    /// The books shown on the shelf itself: everything, less whatever a series card already
    /// shows.
    var shelfBooks: [AudiobookModel] {
        groupSeries ? grouping.standalone : filteredAudiobooks
    }

    /// Books stacked to play next, in queue order.
    var queuedBooks: [AudiobookModel] {
        PlayQueue.shared.books(in: audiobookManager.audiobooks)
    }

    @ViewBuilder
    var seriesBanner: some View {
        SeriesGroupingBanner(
            seriesCount: grouping.series.count,
            bookCount: grouping.series.reduce(0) { $0 + $1.books.count },
            isOn: Binding(
                get: { groupSeries },
                set: { newValue in withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { groupSeries = newValue } }
            )
        )
    }

    // Extracted to help the type-checker
    @ViewBuilder
    var listModeContent: some View {
        List {
            // Statistics Card
            if !audiobookManager.audiobooks.isEmpty {
                StatisticsCardView(statistics: statistics) { showingStatistics = true }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            // Continue Reading Section
            if !continueReadingBooks.isEmpty {
                ContinueReadingSection(books: continueReadingBooks, headerPadding: 0, rowPadding: 4) { playAndPresent($0) }
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

            // Series, grouped by Hardcover
            if !grouping.series.isEmpty {
                seriesBanner
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                if groupSeries {
                    ForEach(grouping.series) { group in
                        SeriesCardView(group: group) { audiobookForDetail = $0 }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                }
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
                // Statistics Card
                if !audiobookManager.audiobooks.isEmpty {
                    StatisticsCardView(statistics: statistics) {
                        showingStatistics = true
                    }
                    .padding(.horizontal)
                }

                // Continue Reading Section
                if !continueReadingBooks.isEmpty {
                    ContinueReadingSection(books: continueReadingBooks, headerPadding: nil, rowPadding: nil) { playAndPresent($0) }
                }

                // Play queue
                if !queuedBooks.isEmpty {
                    QueueSectionView(books: queuedBooks, horizontalPadding: nil, onSelect: playQueued)
                }

                // Series, grouped by Hardcover
                if !grouping.series.isEmpty {
                    VStack(spacing: 12) {
                        seriesBanner
                        if groupSeries {
                            ForEach(grouping.series) { group in
                                SeriesCardView(group: group) { audiobookForDetail = $0 }
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // Main Library Section
                VStack(alignment: .leading, spacing: 16) {
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
                                    AudiobookGridItemView(audiobook: audiobook, columns: gridColumns) { audiobookForDetail = audiobook }
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
        EnhancedAudiobookRowView(audiobook: audiobook) { audiobookForDetail = audiobook }
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
