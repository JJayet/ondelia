import SwiftUI

struct PlayerView: View {
    let audiobook: Audiobook
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var multiFileAudioEngine = MultiFileAudioEngine()
    @StateObject private var audiobookManager = AudiobookManager()
    @State private var showingBookmarks = false
    @State private var showingAddBookmark = false
    @State private var bookmarkTitle = ""
    @State private var bookmarkNote = ""
    @State private var useMultiFileEngine = false
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
        ScrollView {
            VStack(spacing: 24) {
                // Cover Art
                Group {
                    if let image = coverImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "book.closed")
                            .font(.system(size: 80))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 250, height: 250)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(12)
                .shadow(radius: 4)
                
                // Book Info
                VStack(spacing: 8) {
                    Text(audiobook.title ?? "Unknown Title")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                    
                    Text(audiobook.author ?? "Unknown Author")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    if let narrator = audiobook.narrator {
                        Text("Narrated by \(narrator)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Progress Section
                VStack(spacing: 12) {
                    // Time Slider
                    VStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { useMultiFileEngine ? multiFileAudioEngine.currentTime : audioEngine.currentTime },
                                set: { time in
                                    if useMultiFileEngine {
                                        multiFileAudioEngine.seek(to: time)
                                    } else {
                                        audioEngine.seek(to: time)
                                    }
                                }
                            ),
                            in: 0...max(useMultiFileEngine ? multiFileAudioEngine.duration : audioEngine.duration, 1)
                        )
                        
                        HStack {
                            Text(formatTime(useMultiFileEngine ? multiFileAudioEngine.currentTime : audioEngine.currentTime))
                            Spacer()
                            Text(formatTime(useMultiFileEngine ? multiFileAudioEngine.duration : audioEngine.duration))
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    
                    // Playback Controls
                    HStack(spacing: 40) {
                        Button(action: { 
                            if useMultiFileEngine {
                                multiFileAudioEngine.skipBackward()
                            } else {
                                audioEngine.skipBackward()
                            }
                        }) {
                            Image(systemName: "gobackward.15")
                                .font(.title)
                        }
                        
                        Button(action: { 
                            if useMultiFileEngine {
                                multiFileAudioEngine.togglePlayback()
                            } else {
                                audioEngine.togglePlayback()
                            }
                        }) {
                            let isPlaying = useMultiFileEngine ? multiFileAudioEngine.isPlaying : audioEngine.isPlaying
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 64))
                        }
                        
                        Button(action: { 
                            if useMultiFileEngine {
                                multiFileAudioEngine.skipForward()
                            } else {
                                audioEngine.skipForward()
                            }
                        }) {
                            Image(systemName: "goforward.15")
                                .font(.title)
                        }
                    }
                    .foregroundColor(.blue)
                    
                    // Speed Control
                    VStack(spacing: 8) {
                        let playbackRate = useMultiFileEngine ? multiFileAudioEngine.playbackRate : audioEngine.playbackRate
                        Text("Speed: \(String(format: "%.1fx", playbackRate))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 16) {
                            ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                                Button("\(String(format: "%.2fx", speed))") {
                                    if useMultiFileEngine {
                                        multiFileAudioEngine.setPlaybackRate(Float(speed))
                                    } else {
                                        audioEngine.setPlaybackRate(Float(speed))
                                    }
                                }
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(playbackRate == Float(speed) ? Color.blue : Color.gray.opacity(0.2))
                                .foregroundColor(playbackRate == Float(speed) ? .white : .primary)
                                .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                
                // Action Buttons
                HStack(spacing: 20) {
                    Button("Bookmarks") {
                        showingBookmarks = true
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Add Bookmark") {
                        showingAddBookmark = true
                    }
                    .buttonStyle(.bordered)
                }
                
                // Chapters (if available)
                if !chapters.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Chapters")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        LazyVStack(spacing: 8) {
                            ForEach(chapters, id: \.id) { chapter in
                                ChapterRowView(chapter: chapter) {
                                    if useMultiFileEngine {
                                        multiFileAudioEngine.seek(to: chapter.startTime)
                                    } else {
                                        audioEngine.seek(to: chapter.startTime)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadAudiobook()
        }
        .onReceive(useMultiFileEngine ? multiFileAudioEngine.$currentTime : audioEngine.$currentTime) { currentTime in
            // Auto-save progress every 10 seconds
            if Int(currentTime) % 10 == 0 {
                audiobookManager.updateProgress(for: audiobook, currentTime: currentTime)
            }
        }
        .sheet(isPresented: $showingBookmarks) {
            if useMultiFileEngine {
                BookmarksView(audiobook: audiobook, audioEngine: audioEngine) // Pass single engine for compatibility
            } else {
                BookmarksView(audiobook: audiobook, audioEngine: audioEngine)
            }
        }
        .sheet(isPresented: $showingAddBookmark) {
            let currentTime = useMultiFileEngine ? multiFileAudioEngine.currentTime : audioEngine.currentTime
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
    }
    
    private func loadAudiobook() {
        guard let filePath = audiobook.fileURL, !filePath.isEmpty else { 
            print("No file path found for audiobook: \(audiobook.title ?? "Unknown")")
            return 
        }
        
        // Check if it's a folder (multi-file audiobook) or single file
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: filePath, isDirectory: &isDirectory) else {
            print("Audio file/folder not found at path: \(filePath)")
            return
        }
        
        if isDirectory.boolValue {
            print("📁 Loading multi-file audiobook from folder: \(filePath)")
            useMultiFileEngine = true
            multiFileAudioEngine.loadMultiFileAudiobook(audiobook)
            
            // Resume from last position
            if audiobook.currentPosition > 0 {
                multiFileAudioEngine.seek(to: audiobook.currentPosition)
            }
        } else {
            print("📄 Loading single audio file: \(filePath)")
            useMultiFileEngine = false
            let fileURL = URL(fileURLWithPath: filePath)
            audioEngine.loadAudio(url: fileURL)
            
            // Resume from last position
            if audiobook.currentPosition > 0 {
                audioEngine.seek(to: audiobook.currentPosition)
            }
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

struct ChapterRowView: View {
    let chapter: Chapter
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    NavigationView {
        PlayerView(audiobook: Audiobook())
    }
}