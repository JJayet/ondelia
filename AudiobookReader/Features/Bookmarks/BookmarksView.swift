import SwiftUI

struct BookmarksView: View {
    let audiobook: Audiobook
    let audioEngine: AudioEngine
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
                        
                        Text("No Bookmarks")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Add bookmarks to save specific moments in this audiobook")
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
                                    audioEngine.seek(to: bookmark.timestamp)
                                    presentationMode.wrappedValue.dismiss()
                                },
                                onDelete: {
                                    audiobookManager.deleteBookmark(bookmark)
                                }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
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
                    Text(bookmark.title ?? "Bookmark")
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
            Button("Delete") {
                showingDeleteAlert = true
            }
            .tint(.red)
        }
        .alert("Delete Bookmark", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete this bookmark?")
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
                Section("Bookmark Details") {
                    TextField("Title", text: $title)
                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Bookmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
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
    BookmarksView(audiobook: Audiobook(), audioEngine: AudioEngine())
}