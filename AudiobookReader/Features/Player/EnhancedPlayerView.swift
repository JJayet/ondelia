import SwiftUI

struct EnhancedPlayerView: View {
    let audiobook: Audiobook
    @ObservedObject var statistics: ReadingStatistics
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var multiFileAudioEngine = MultiFileAudioEngine()
    @StateObject private var audiobookManager = AudiobookManager()
    @StateObject private var themeManager = ThemeManager.shared
    @State private var useMultiFileEngine = false
    @State private var showingBookmarks = false
    @State private var showingAddBookmark = false
    @State private var showingSleepTimer = false
    @State private var bookmarkTitle = ""
    @State private var bookmarkNote = ""
    @State private var sleepTimer: Timer?
    @State private var sleepTimeRemaining: TimeInterval = 0
    @State private var isSeekingManually = false
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
    
    private var currentChapter: Chapter? {
        let currentTime = useMultiFileEngine ? multiFileAudioEngine.currentTime : audioEngine.currentTime
        return chapters.first { chapter in
            currentTime >= chapter.startTime && currentTime < chapter.endTime
        } ?? chapters.first { chapter in
            currentTime >= chapter.startTime
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                LinearGradient(
                    colors: [
                        Color.primaryBackground,
                        Color.secondaryBackground.opacity(0.3)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Header
                        HStack {
                            Button {
                                presentationMode.wrappedValue.dismiss()
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.title2)
                                    .foregroundColor(.primaryText)
                            }
                            
                            Spacer()
                            
                            Button {
                                showingSleepTimer = true
                            } label: {
                                if sleepTimeRemaining > 0 {
                                    Label(formatTime(sleepTimeRemaining), systemImage: "moon.fill")
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
                                } else {
                                    Image(systemName: "moon")
                                        .font(.title2)
                                        .foregroundColor(.primaryText)
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // Cover Art with Animation
                        Group {
                            if let image = coverImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } else {
                                Image(systemName: "book.closed")
                                    .font(.system(size: 120))
                                    .foregroundColor(.secondaryText)
                            }
                        }
                        .frame(width: geometry.size.width * 0.7, height: geometry.size.width * 0.7)
                        .background(Color.secondaryBackground)
                        .cornerRadius(20)
                        .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
                        .scaleEffect((useMultiFileEngine ? multiFileAudioEngine.isPlaying : audioEngine.isPlaying) ? 1.02 : 1.0)
                        .animation(.easeInOut(duration: 0.3), value: useMultiFileEngine ? multiFileAudioEngine.isPlaying : audioEngine.isPlaying)
                        .onTapGesture {
                            withHapticFeedback {
                                if useMultiFileEngine {
                                    multiFileAudioEngine.togglePlayback()
                                } else {
                                    audioEngine.togglePlayback()
                                }
                            }
                        }
                        .gesture(
                            DragGesture()
                                .onEnded { value in
                                    if abs(value.translation.width) > 50 {
                                        withHapticFeedback {
                                            if value.translation.width > 0 {
                                                if useMultiFileEngine {
                                                    multiFileAudioEngine.skipBackward(themeManager.skipInterval.seconds)
                                                } else {
                                                    audioEngine.skipBackward(themeManager.skipInterval.seconds)
                                                }
                                            } else {
                                                if useMultiFileEngine {
                                                    multiFileAudioEngine.skipForward(themeManager.skipInterval.seconds)
                                                } else {
                                                    audioEngine.skipForward(themeManager.skipInterval.seconds)
                                                }
                                            }
                                        }
                                    }
                                }
                        )
                        
                        // Book Info
                        VStack(spacing: 8) {
                            Text(audiobook.title ?? "Unknown Title")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.primaryText)
                                .multilineTextAlignment(.center)
                            
                            Text(audiobook.author ?? "Unknown Author")
                                .font(.headline)
                                .foregroundColor(.secondaryText)
                            
                            if let narrator = audiobook.narrator {
                                Text("Narrated by \(narrator)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondaryText)
                            }
                            
                            // Current Chapter
                            if let chapter = currentChapter {
                                Text(chapter.title ?? "Chapter \(chapter.chapterNumber)")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.1))
                                    .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal)
                        
                        // Progress Section
                        VStack(spacing: 16) {
                            // Time Slider with Custom Style
                            VStack(spacing: 8) {
                                CustomSlider(
                                    value: Binding(
                                        get: { useMultiFileEngine ? multiFileAudioEngine.currentTime : audioEngine.currentTime },
                                        set: { newValue in
                                            if useMultiFileEngine {
                                                multiFileAudioEngine.seek(to: newValue)
                                            } else {
                                                audioEngine.seek(to: newValue)
                                            }
                                        }
                                    ),
                                    range: 0...max(useMultiFileEngine ? multiFileAudioEngine.duration : audioEngine.duration, 1),
                                    onEditingChanged: { editing in
                                        isSeekingManually = editing
                                    }
                                )
                                
                                HStack {
                                    Text(formatTime(useMultiFileEngine ? multiFileAudioEngine.currentTime : audioEngine.currentTime))
                                        .font(.caption)
                                        .foregroundColor(.secondaryText)
                                        .monospacedDigit()
                                    
                                    Spacer()
                                    
                                    Text(formatTime(useMultiFileEngine ? multiFileAudioEngine.duration : audioEngine.duration))
                                        .font(.caption)
                                        .foregroundColor(.secondaryText)
                                        .monospacedDigit()
                                }
                            }
                            
                            // Enhanced Playback Controls
                            HStack(spacing: 50) {
                                Button {
                                    withHapticFeedback {
                                        if useMultiFileEngine {
                                            multiFileAudioEngine.skipBackward(themeManager.skipInterval.seconds)
                                        } else {
                                            audioEngine.skipBackward(themeManager.skipInterval.seconds)
                                        }
                                    }
                                } label: {
                                    Image(systemName: "gobackward.\(Int(themeManager.skipInterval.seconds))")
                                        .font(.title)
                                        .foregroundColor(.primaryText)
                                }
                                
                                Button {
                                    withHapticFeedback(.medium) {
                                        if useMultiFileEngine {
                                            multiFileAudioEngine.togglePlayback()
                                        } else {
                                            audioEngine.togglePlayback()
                                        }
                                    }
                                } label: {
                                    let isPlaying = useMultiFileEngine ? multiFileAudioEngine.isPlaying : audioEngine.isPlaying
                                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 80))
                                        .foregroundColor(.accentColor)
                                }
                                .scaleEffect((useMultiFileEngine ? multiFileAudioEngine.isPlaying : audioEngine.isPlaying) ? 0.95 : 1.0)
                                .animation(.easeInOut(duration: 0.1), value: useMultiFileEngine ? multiFileAudioEngine.isPlaying : audioEngine.isPlaying)
                                
                                Button {
                                    withHapticFeedback {
                                        if useMultiFileEngine {
                                            multiFileAudioEngine.skipForward(themeManager.skipInterval.seconds)
                                        } else {
                                            audioEngine.skipForward(themeManager.skipInterval.seconds)
                                        }
                                    }
                                } label: {
                                    Image(systemName: "goforward.\(Int(themeManager.skipInterval.seconds))")
                                        .font(.title)
                                        .foregroundColor(.primaryText)
                                }
                            }
                            
                            // Speed Control with Animation
                            VStack(spacing: 12) {
                                let playbackRate = useMultiFileEngine ? multiFileAudioEngine.playbackRate : audioEngine.playbackRate
                                Text("Speed: \(String(format: "%.1fx", playbackRate))")
                                    .font(.caption)
                                    .foregroundColor(.secondaryText)
                                
                                HStack(spacing: 12) {
                                    ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                                        Button("\(String(format: "%.2fx", speed))") {
                                            withHapticFeedback {
                                                if useMultiFileEngine {
                                                    multiFileAudioEngine.setPlaybackRate(Float(speed))
                                                } else {
                                                    audioEngine.setPlaybackRate(Float(speed))
                                                }
                                            }
                                        }
                                        .font(.caption)
                                        .fontWeight(playbackRate == Float(speed) ? .bold : .regular)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(
                                            playbackRate == Float(speed) 
                                                ? Color.accentColor 
                                                : Color.secondaryBackground
                                        )
                                        .foregroundColor(
                                            playbackRate == Float(speed) 
                                                ? .white 
                                                : .primaryText
                                        )
                                        .cornerRadius(20)
                                        .scaleEffect(playbackRate == Float(speed) ? 1.1 : 1.0)
                                        .animation(.easeInOut(duration: 0.2), value: playbackRate)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // Action Buttons
                        HStack(spacing: 32) {
                            ActionButton(icon: "bookmark", title: "Bookmarks", count: bookmarks.count) {
                                showingBookmarks = true
                            }
                            
                            ActionButton(icon: "bookmark.circle", title: "Add Bookmark") {
                                showingAddBookmark = true
                            }
                            
                            if !chapters.isEmpty {
                                ActionButton(icon: "list.bullet", title: "Chapters", count: chapters.count) {
                                    // Show chapters view
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        Spacer(minLength: 50)
                    }
                    .padding(.vertical)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            loadAudiobook()
        }
        .onReceive(useMultiFileEngine ? multiFileAudioEngine.$currentTime : audioEngine.$currentTime) { currentTime in
            // Auto-save progress every 10 seconds
            if Int(currentTime) % 10 == 0 && !isSeekingManually {
                audiobookManager.updateProgress(for: audiobook, currentTime: currentTime)
                statistics.addListeningTime(10, playbackRate: useMultiFileEngine ? multiFileAudioEngine.playbackRate : audioEngine.playbackRate)
                
                if audiobook.isFinished && !audiobook.isFinished {
                    statistics.markBookCompleted()
                }
            }
        }
        .sheet(isPresented: $showingBookmarks) {
            BookmarksView(audiobook: audiobook, audioEngine: audioEngine)
        }
        .sheet(isPresented: $showingAddBookmark) {
            AddBookmarkView(
                title: $bookmarkTitle,
                note: $bookmarkNote,
                onSave: {
                    let currentTime = useMultiFileEngine ? multiFileAudioEngine.currentTime : audioEngine.currentTime
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
        .actionSheet(isPresented: $showingSleepTimer) {
            ActionSheet(
                title: Text("Sleep Timer"),
                message: Text("Choose when to stop playback"),
                buttons: [
                    .default(Text("5 minutes")) { setSleepTimer(300) },
                    .default(Text("10 minutes")) { setSleepTimer(600) },
                    .default(Text("15 minutes")) { setSleepTimer(900) },
                    .default(Text("30 minutes")) { setSleepTimer(1800) },
                    .default(Text("End of chapter")) { setSleepTimerEndOfChapter() },
                    .destructive(Text("Cancel timer")) { cancelSleepTimer() },
                    .cancel()
                ]
            )
        }
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        .accentColor(themeManager.accentColor.color)
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
    
    private func setSleepTimer(_ seconds: TimeInterval) {
        cancelSleepTimer()
        sleepTimeRemaining = seconds
        
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            sleepTimeRemaining -= 1
            
            if sleepTimeRemaining <= 0 {
                if useMultiFileEngine {
                    multiFileAudioEngine.pause()
                } else {
                    audioEngine.pause()
                }
                timer.invalidate()
                sleepTimer = nil
            }
        }
    }
    
    private func setSleepTimerEndOfChapter() {
        guard let currentChapter = currentChapter else { return }
        let currentTime = useMultiFileEngine ? multiFileAudioEngine.currentTime : audioEngine.currentTime
        let remainingTime = currentChapter.endTime - currentTime
        setSleepTimer(max(remainingTime, 60)) // Minimum 1 minute
    }
    
    private func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimeRemaining = 0
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
    
    private func withHapticFeedback<T>(_ intensity: UIImpactFeedbackGenerator.FeedbackStyle = .light, _ action: () -> T) -> T {
        let impact = UIImpactFeedbackGenerator(style: intensity)
        impact.prepare()
        let result = action()
        impact.impactOccurred()
        return result
    }
}

struct ActionButton: View {
    let icon: String
    let title: String
    var count: Int? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(.accentColor)
                    
                    if let count = count, count > 0 {
                        Text("\(count)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.red)
                            .clipShape(Circle())
                            .offset(x: 12, y: -12)
                    }
                }
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primaryText)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct CustomSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onEditingChanged: (Bool) -> Void
    @State private var isDragging = false
    @State private var localValue: Double = 0
    
    var body: some View {
        GeometryReader { geometry in
            let percentage = (isDragging ? localValue : value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let clampedPercentage = min(max(percentage, 0), 1)
            
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondaryBackground)
                    .frame(height: 4)
                
                // Progress
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * clampedPercentage, height: 4)
                
                // Thumb
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: isDragging ? 24 : 20, height: isDragging ? 24 : 20)
                    .offset(x: geometry.size.width * clampedPercentage - (isDragging ? 12 : 10))
                    .animation(.easeInOut(duration: 0.1), value: isDragging)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            localValue = value - range.lowerBound
                            onEditingChanged(true)
                        }
                        
                        let percentage = max(0, min(1, gesture.location.x / geometry.size.width))
                        localValue = (range.upperBound - range.lowerBound) * percentage
                        value = range.lowerBound + localValue
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
            .onTapGesture { location in
                let percentage = max(0, min(1, location.x / geometry.size.width))
                let newValue = range.lowerBound + (range.upperBound - range.lowerBound) * percentage
                value = newValue
            }
        }
        .frame(height: 44) // Larger touch target
        .onAppear {
            localValue = value - range.lowerBound
        }
    }
}

#Preview {
    EnhancedPlayerView(audiobook: Audiobook(), statistics: ReadingStatistics())
}
