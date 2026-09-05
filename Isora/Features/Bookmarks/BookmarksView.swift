import SwiftUI

struct BookmarksView: View {
    let audiobook: AudiobookModel
    let globalAudioManager: GlobalAudioManager
    private let audiobookManager = AudiobookManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingAdd = false
    @State private var newTitle = ""
    @State private var newNote = ""
    
    private var bookmarks: [BookmarkModel] {
        audiobook.bookmarks.sorted { $0.timestamp < $1.timestamp }
    }

    /// Where the new bookmark lands: the live position when this book is playing, otherwise
    /// where the book was left.
    private var bookmarkTime: TimeInterval {
        globalAudioManager.currentAudiobook?.id == audiobook.id
            ? globalAudioManager.getCurrentTime()
            : audiobook.currentPosition
    }

    private func addBookmark() {
        let time = bookmarkTime
        audiobookManager.createBookmark(
            for: audiobook,
            at: time,
            title: newTitle.isEmpty
                ? String(
                    format: NSLocalizedString("Bookmark at %@", comment: "Default bookmark title with time"),
                    time.clockFormatted
                ) : newTitle,
            note: newNote.isEmpty ? nil : newNote
        )
        newTitle = ""
        newNote = ""
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if bookmarks.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        
                        Text(NSLocalizedString("No bookmarks yet", comment: "No bookmarks empty state title"))
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text(NSLocalizedString("Tap + to bookmark the current position", comment: "No bookmarks instructions"))
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    List {
                        ForEach(bookmarks, id: \.id) { bookmark in
                            BookmarkRowView(
                                bookmark: bookmark,
                                onTap: {
                                    Log.ui.debug("🔖 Seeking to bookmark at \(bookmark.timestamp) seconds")
                                    // The bookmark belongs to this book, which is not
                                    // necessarily the one playing: browsing another book's
                                    // bookmarks used to move the playing one instead.
                                    globalAudioManager.loadAudiobook(audiobook)
                                    globalAudioManager.seek(to: bookmark.timestamp)
                                    dismiss()
                                },
                                onDelete: {
                                    audiobookManager.deleteBookmark(bookmark)
                                }
                            )
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Bookmarks", comment: "Bookmarks view title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: {
                        Label(NSLocalizedString("Add Bookmark", comment: "Add bookmark button title"), systemImage: "plus")
                    }
                    .accessibilityIdentifier(AccessibilityIdentifiers.Player.addBookmarkButton)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Done", comment: "Done button")) { dismiss() }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddBookmarkView(title: $newTitle, note: $newNote, onSave: addBookmark)
            }
        }
    }
}

struct BookmarkRowView: View {
    let bookmark: BookmarkModel
    let onTap: () -> Void
    let onDelete: () -> Void
    @State private var showingDeleteAlert = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(bookmark.title ?? NSLocalizedString("Bookmark", comment: "Default bookmark title"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Text(bookmark.timestamp.clockFormatted)
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(.rect(cornerRadius: 4))
                }
                
                if let note = bookmark.note, !note.isEmpty {
                    Text(note)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                
                Text(formatDate(bookmark.dateCreated))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(NSLocalizedString("Delete", comment: "Delete bookmark button")) {
                showingDeleteAlert = true
            }
            .tint(.red)
        }
        .alert(NSLocalizedString("Delete Bookmark", comment: "Delete bookmark alert title"), isPresented: $showingDeleteAlert) {
            Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) { }
            Button(NSLocalizedString("Delete", comment: "Delete button"), role: .destructive) {
                onDelete()
            }
        } message: {
            Text(NSLocalizedString("Are you sure you want to delete this bookmark?", comment: "Delete bookmark confirmation message"))
        }
    }
    
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "" }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct AddBookmarkView: View {
    @Binding var title: String
    @Binding var note: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section(NSLocalizedString("Bookmark Details", comment: "Bookmark details form section header")) {
                    TextField(NSLocalizedString("Bookmark Title", comment: "Bookmark title text field placeholder"), text: $title)
                    TextField(NSLocalizedString("Note (Optional)", comment: "Bookmark note text field placeholder"), text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(NSLocalizedString("Add Bookmark", comment: "Add bookmark view title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "Cancel button")) { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Save", comment: "Save button")) { onSave(); dismiss() }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview("Empty") {
    BookmarksView(audiobook: PreviewContent.audiobookLong(), globalAudioManager: GlobalAudioManager.shared)
}


#Preview("With bookmarks") {
    BookmarksView(audiobook: PreviewContent.audiobookFinished(), globalAudioManager: GlobalAudioManager.shared)
}
