import SwiftUI

// MARK: - List / Grid content
extension LibraryView {
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

            // Header with filters
            LibraryHeaderView(
                viewMode: $viewMode,
                sortOption: $sortOption,
                filterOption: $filterOption
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            // Library Items
            if audiobookManager.audiobooks.isEmpty && !audiobookManager.isImporting {
                EmptyLibraryView()
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

                ForEach(filteredAudiobooks, id: \.id, content: libraryRow)
            }
        }
        .listStyle(PlainListStyle())
        .background(Color.primaryBackground)
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

                // Main Library Section
                VStack(alignment: .leading, spacing: 16) {
                    // Header with filters
                    LibraryHeaderView(
                        viewMode: $viewMode,
                        sortOption: $sortOption,
                        filterOption: $filterOption
                    )
                    .padding(.horizontal)

                    // Content
                    if audiobookManager.audiobooks.isEmpty && !audiobookManager.isImporting {
                        EmptyLibraryView()
                        .padding(.horizontal)
                    } else {
                        VStack(spacing: 16) {
                            if audiobookManager.isImporting {
                                ImportingIndicatorView(manager: audiobookManager)
                                    .padding(.horizontal)
                            }

                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16)
                            ], spacing: 16) {
                                ForEach(filteredAudiobooks, id: \.id) { audiobook in
                                    AudiobookGridItemView(audiobook: audiobook) { playAndPresent(audiobook) }
                                    .contextMenu {
                                        Button(NSLocalizedString("Rename", comment: "Rename button")) {
                                            audiobookToRename = audiobook
                                            newAudiobookTitle = audiobook.title ?? ""
                                            showingRenameAlert = true
                                        }

                                        Button(audiobook.isFinished ? NSLocalizedString("Mark as Unread", comment: "Mark as unread") : NSLocalizedString("Mark as Read", comment: "Mark as read")) {
                                            if audiobook.isFinished {
                                                audiobookManager.markAsUnread(audiobook)
                                            } else {
                                                audiobookManager.markAsRead(audiobook)
                                            }
                                        }

                                        Button(NSLocalizedString("Change Cover Image", comment: "Change cover image button")) {
                                            audiobookForImagePicker = audiobook
                                        }

                                        Button(NSLocalizedString("Delete", comment: "Delete button"), role: .destructive) {
                                            audiobookManager.deleteAudiobook(audiobook)
                                        }
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
        EnhancedAudiobookRowView(audiobook: audiobook) { playAndPresent(audiobook) }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(NSLocalizedString("Delete", comment: "Delete button")) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        audiobookManager.deleteAudiobook(audiobook)
                    }
                }
                .tint(.red)
            }
            .swipeActions(edge: .leading) {
                Button(audiobook.isFinished ? NSLocalizedString("Mark Unread", comment: "Mark as unread") : NSLocalizedString("Mark Read", comment: "Mark as read")) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        if audiobook.isFinished {
                            audiobookManager.markAsUnread(audiobook)
                        } else {
                            audiobookManager.markAsRead(audiobook)
                        }
                    }
                }
                .tint(audiobook.isFinished ? .orange : .green)

                Button(NSLocalizedString("Rename", comment: "Rename button")) {
                    audiobookToRename = audiobook
                    newAudiobookTitle = audiobook.title ?? ""
                    showingRenameAlert = true
                }
                .tint(.blue)
            }
            .contextMenu {
                Button(NSLocalizedString("Rename", comment: "Rename button")) {
                    audiobookToRename = audiobook
                    newAudiobookTitle = audiobook.title ?? ""
                    showingRenameAlert = true
                }

                Button(audiobook.isFinished ? NSLocalizedString("Mark as Unread", comment: "Mark as unread") : NSLocalizedString("Mark as Read", comment: "Mark as read")) {
                    if audiobook.isFinished {
                        audiobookManager.markAsUnread(audiobook)
                    } else {
                        audiobookManager.markAsRead(audiobook)
                    }
                }

                Button(NSLocalizedString("Change Cover Image", comment: "Change cover image button")) {
                    audiobookForImagePicker = audiobook
                }
            }
    }
}
