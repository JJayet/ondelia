import SwiftUI

struct BookmarksView: View {
    let audiobook: Audiobook
    @ObservedObject var globalAudioManager: GlobalAudioManager
    @StateObject private var audiobookManager = AudiobookManager()
    @Environment(\.presentationMode) var presentationMode
    
    private var bookmarks: [Bookmark] {
        (audiobook.bookmarks?.allObjects as? [Bookmark] ?? []).sorted { $0.timestamp < $1.timestamp }
    }
    
    var body: some View {
        NavigationView {
            Group {
                if bookmarks.isEmpty {
                    // Empty State
                    VStack(spacing: 20) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text(NSLocalizedString("No bookmarks yet", comment: "No bookmarks empty state title"))
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text(NSLocalizedString("Create your first bookmark by tapping the bookmark button while listening", comment: "No bookmarks instructions"))
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    List {
                        ForEach(bookmarks, id: \.id) { bookmark in
                            BookmarkRowView(
                                bookmark: bookmark,
                                onTap: {
                                    print("🔖 Seeking to bookmark at \(bookmark.timestamp) seconds")
                                    globalAudioManager.seek(to: bookmark.timestamp)
                                    
                                    // Dismiss the sheet after a short delay to let the seek complete
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        presentationMode.wrappedValue.dismiss()
                                    }
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
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("Done", comment: "Done button")) {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

struct BookmarkRowView: View {
    let bookmark: Bookmark
    let onTap: () -> Void
    let onDelete: () -> Void
    @State private var showingDeleteAlert = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(bookmark.title ?? NSLocalizedString("Bookmark", comment: "Default bookmark title"))
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text(formatTime(bookmark.timestamp))
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                }
                
                if let note = bookmark.note, !note.isEmpty {
                    Text(note)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
                
                Text(formatDate(bookmark.dateCreated))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
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
    
    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
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
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
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
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("Cancel", comment: "Cancel button")) {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Save", comment: "Save button")) {
                        onSave()
                        presentationMode.wrappedValue.dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    BookmarksView(audiobook: Audiobook(), globalAudioManager: GlobalAudioManager.shared)
}