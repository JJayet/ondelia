import SwiftUI

struct PlayerView: View {
    let audiobook: Audiobook
    @StateObject private var globalAudioManager = GlobalAudioManager.shared
    @StateObject private var audiobookManager = AudiobookManager()
    @State private var showingBookmarks = false
    @State private var showingAddBookmark = false
    @State private var showingChapterList = false
    @State private var bookmarkTitle = ""
    @State private var bookmarkNote = ""
    @Environment(\.presentationMode) var presentationMode
    
    private var coverImage: UIImage? {
        guard let data = audiobook.coverImageData else { return nil }
        return UIImage(data: data)
    }
    
    private var chapters: [Chapter] {
        (audiobook.chapters?.allObjects as? [Chapter] ?? []).sorted { $0.chapterNumber < $1.chapterNumber }
    }
    
    private var bookmarks: [Bookmark] {
        (audiobook.bookmarks?.allObjects as? [Bookmark] ?? []).sorted { $0.timestamp < $1.timestamp }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Cover Art - Smaller and more appropriate size
            Group {
                if let image = coverImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "book.closed")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 180, height: 180)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(12)
            .shadow(radius: 4)
                
            // Book Info - More compact
            VStack(spacing: 4) {
                Text(audiobook.title ?? "Unknown Title")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                Text(audiobook.author ?? "Unknown Author")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if let narrator = audiobook.narrator {
                    Text("Narrated by \(narrator)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
                
            // Progress Section
            VStack(spacing: 8) {
                // Time Slider
                Slider(
                    value: Binding(
                        get: { globalAudioManager.getCurrentTime() },
                        set: { time in
                            if globalAudioManager.useMultiFileEngine {
                                globalAudioManager.multiFileAudioEngine?.seek(to: time)
                            } else {
                                globalAudioManager.audioEngine?.seek(to: time)
                            }
                        }
                    ),
                    in: 0...max(globalAudioManager.getDuration(), 1)
                )
                
                HStack {
                    Text(formatTime(globalAudioManager.getCurrentTime()))
                    Spacer()
                    Text(formatTime(globalAudioManager.getDuration()))
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal)
                    
            // Playback Controls
            HStack(spacing: 40) {
                Button(action: { 
                    if globalAudioManager.useMultiFileEngine {
                        globalAudioManager.multiFileAudioEngine?.skipBackward()
                    } else {
                        globalAudioManager.audioEngine?.skipBackward()
                    }
                }) {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                }
                
                Button(action: { 
                    if globalAudioManager.isPlaying() {
                        globalAudioManager.pausePlayback()
                    } else {
                        globalAudioManager.resumePlayback()
                    }
                }) {
                    Image(systemName: globalAudioManager.isPlaying() ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 50))
                }
                
                Button(action: { 
                    if globalAudioManager.useMultiFileEngine {
                        globalAudioManager.multiFileAudioEngine?.skipForward()
                    } else {
                        globalAudioManager.audioEngine?.skipForward()
                    }
                }) {
                    Image(systemName: "goforward.15")
                        .font(.title2)
                }
            }
            .foregroundColor(.blue)
                    
            VStack(spacing: 4) {
                let playbackRate = globalAudioManager.getPlaybackRate()
                Text("Speed: \(String(format: "%.1fx", playbackRate))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                        Button("\(String(format: "%.2fx", speed))") {
                            if globalAudioManager.useMultiFileEngine {
                                globalAudioManager.multiFileAudioEngine?.setPlaybackRate(Float(speed))
                            } else {
                                globalAudioManager.audioEngine?.setPlaybackRate(Float(speed))
                            }
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(playbackRate == Float(speed) ? Color.blue : Color.gray.opacity(0.2))
                        .foregroundColor(playbackRate == Float(speed) ? .white : .primary)
                        .cornerRadius(6)
                    }
                }
            }
                
            // Action Buttons
            HStack(spacing: 10) {
                Button("Bookmarks") {
                    showingBookmarks = true
                }
                .buttonStyle(.bordered)
                
                Button("Add Bookmark") {
                    showingAddBookmark = true
                }
                .buttonStyle(.bordered)
                
                // Chapters Button (if available)
                if !chapters.isEmpty {
                    Button("Chapters (\(chapters.count))") {
                        print("📖 Chapter button tapped - showing chapter list")
                        showingChapterList = true
                    }
                    .buttonStyle(.bordered)
                } else {
                    // Debug: Show even when no chapters for testing
                    Button("No Chapters (Debug)") {
                        print("📖 No chapters found for audiobook: \(audiobook.title ?? "Unknown")")
                        print("📖 Chapters in audiobook: \(audiobook.chapters?.count ?? 0)")
                    }
                    .buttonStyle(.bordered)
                    .opacity(0.5)
                }
            }
            
            Spacer()
        }
        .padding()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            globalAudioManager.loadAudiobook(audiobook)
        }
        .onReceive(globalAudioManager.$audioEngine) { _ in
            // Trigger UI updates when audio engine changes
        }
        .onReceive(globalAudioManager.$multiFileAudioEngine) { _ in
            // Trigger UI updates when multi-file engine changes
        }
        .sheet(isPresented: $showingBookmarks) {
            // For now, pass a dummy AudioEngine - we'll need to update BookmarksView later
            if let engine = globalAudioManager.audioEngine {
                BookmarksView(audiobook: audiobook, audioEngine: engine)
            }
        }
        .sheet(isPresented: $showingAddBookmark) {
            let currentTime = globalAudioManager.getCurrentTime()
            AddBookmarkView(
                title: $bookmarkTitle,
                note: $bookmarkNote,
                onSave: {
                    audiobookManager.createBookmark(
                        for: audiobook,
                        at: currentTime,
                        title: bookmarkTitle.isEmpty ? "Bookmark at \(formatTime(currentTime))" : bookmarkTitle,
                        note: bookmarkNote.isEmpty ? nil : bookmarkNote
                    )
                    bookmarkTitle = ""
                    bookmarkNote = ""
                }
            )
        }
        .sheet(isPresented: $showingChapterList) {
            ChapterListView(
                chapters: chapters,
                onChapterTap: { chapter in
                    if globalAudioManager.useMultiFileEngine {
                        globalAudioManager.multiFileAudioEngine?.seek(to: chapter.startTime)
                    } else {
                        globalAudioManager.audioEngine?.seek(to: chapter.startTime)
                    }
                    showingChapterList = false
                }
            )
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
}

struct ChapterListView: View {
    let chapters: [Chapter]
    let onChapterTap: (Chapter) -> Void
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            List {
                ForEach(chapters, id: \.id) { chapter in
                    ChapterRowView(chapter: chapter) {
                        onChapterTap(chapter)
                    }
                }
            }
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

struct ChapterRowView: View {
    let chapter: Chapter
    let onTap: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.title ?? "Chapter \(chapter.chapterNumber)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(formatTime(chapter.startTime))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "play.fill")
                .font(.caption)
                .foregroundColor(.blue)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle()) // Make entire area tappable
        .onTapGesture {
            print("📖 Chapter tapped: \(chapter.title ?? "Chapter \(chapter.chapterNumber)") at \(formatTime(chapter.startTime))")
            onTap()
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
}

#Preview {
    NavigationView {
        PlayerView(audiobook: Audiobook())
    }
}
