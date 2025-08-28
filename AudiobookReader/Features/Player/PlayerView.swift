import SwiftUI
import UIKit

struct PlayerView: View {
    let audiobook: Audiobook
    @ObservedObject var statistics: ReadingStatistics
    @StateObject private var audiobookManager = AudiobookManager()
    @StateObject private var themeManager = ThemeManager.shared
    @ObservedObject private var globalAudioManager = GlobalAudioManager.shared
    @State private var showingBookmarks = false
    @State private var showingAddBookmark = false
    @State private var showingSleepTimer = false
    @State private var showingChapterList = false
    @State private var showingTranscription = false
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
        let currentTime = globalAudioManager.getCurrentTime()
        return chapters.first { chapter in
            currentTime >= chapter.startTime && currentTime < chapter.endTime
        } ?? chapters.first { chapter in
            currentTime >= chapter.startTime
        }
    }
    
    private var isPlaying: Bool {
        // Use the published playback state for better UI responsiveness
        return globalAudioManager.playbackState == .playing
    }
    
    private var currentTime: TimeInterval {
        globalAudioManager.getCurrentTime()
    }
    
    private var duration: TimeInterval {
        globalAudioManager.getDuration()
    }
    
    private var playbackRate: Float {
        globalAudioManager.getPlaybackRate()
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
                    VStack(spacing: 24) {
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
                        
                        // Cover Art with Animation - Made smaller for compact layout
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
                        .frame(width: geometry.size.width * 0.5, height: geometry.size.width * 0.5)
                        .background(Color.secondaryBackground)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.15), radius: 15, x: 0, y: 8)
                        .scaleEffect(isPlaying ? 1.02 : 1.0)
                        .animation(.easeInOut(duration: 0.3), value: isPlaying)
                        .onTapGesture {
                            withHapticFeedback {
                                if isPlaying {
                                    globalAudioManager.pausePlayback()
                                } else {
                                    globalAudioManager.startPlayback()
                                }
                            }
                        }
                        .gesture(
                            DragGesture()
                                .onEnded { value in
                                    if abs(value.translation.width) > 50 {
                                        withHapticFeedback {
                                            if value.translation.width > 0 {
                                                globalAudioManager.skipBackward(themeManager.skipInterval.seconds)
                                            } else {
                                                globalAudioManager.skipForward(themeManager.skipInterval.seconds)
                                            }
                                        }
                                    }
                                }
                        )
                        
                        // Book Info
                        VStack(spacing: 8) {
                            Text(audiobook.title ?? NSLocalizedString("Unknown Title", comment: "Default title for audiobooks without title"))
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.primaryText)
                                .multilineTextAlignment(.center)
                            
                            Text(audiobook.author ?? NSLocalizedString("Unknown Author", comment: "Default author for audiobooks without author"))
                                .font(.subheadline)
                                .foregroundColor(.secondaryText)
                            
                            if let narrator = audiobook.narrator {
                                Text(String(format: NSLocalizedString("Narrated by %@", comment: "Narrator credit text"), narrator))
                                    .font(.caption)
                                    .foregroundColor(.secondaryText)
                            }
                            
                            // Current Chapter
                            if let chapter = currentChapter {
                                Text(chapter.title ?? String(format: NSLocalizedString("Chapter %d", comment: "Default chapter title with number"), chapter.chapterNumber))
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
                                        get: { currentTime },
                                        set: { newValue in
                                            globalAudioManager.seek(to: newValue)
                                        }
                                    ),
                                    range: 0...max(duration, 1),
                                    onEditingChanged: { editing in
                                        isSeekingManually = editing
                                    }
                                )
                                .accessibilityIdentifier(AccessibilityIdentifiers.Player.progressSlider)
                                .accessibilityLabel(NSLocalizedString("Audio progress", comment: "Accessibility label for progress slider"))
                                .accessibilityValue(formatAccessibilityTime(currentTime, duration: duration))
                                .accessibilityAdjustableAction { direction in
                                    let increment: TimeInterval = 30
                                    let newTime = direction == .increment ? 
                                        min(currentTime + increment, duration) :
                                        max(currentTime - increment, 0)
                                    
                                    globalAudioManager.seek(to: newTime)
                                }
                                
                                HStack {
                                    Text(formatTime(currentTime))
                                        .font(.caption)
                                        .foregroundColor(.secondaryText)
                                        .monospacedDigit()
                                    
                                    Spacer()
                                    
                                    Text(formatTime(duration))
                                        .font(.caption)
                                        .foregroundColor(.secondaryText)
                                        .monospacedDigit()
                                }
                            }
                            
                            Spacer()
                            HStack(spacing: 40) {
                                Button {
                                    withHapticFeedback {
                                        globalAudioManager.skipBackward(themeManager.skipInterval.seconds)
                                    }
                                } label: {
                                    Image(systemName: "gobackward.\(Int(themeManager.skipInterval.seconds))")
                                        .font(.title)
                                        .foregroundColor(.primaryText)
                                }
                                
                                Button {
                                    withHapticFeedback(.medium) {
                                        if globalAudioManager.playbackState != .loading {
                                            globalAudioManager.togglePlayback()
                                        }
                                    }
                                } label: {
                                    Group {
                                        if globalAudioManager.playbackState == .loading {
                                            ProgressView()
                                                .scaleEffect(1.8)
                                                .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
                                        } else {
                                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                                .font(.system(size: 70))
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                }
                                .frame(width: 70, height: 70)
                                .scaleEffect(isPlaying && globalAudioManager.playbackState != .loading ? 0.95 : 1.0)
                                .animation(.easeInOut(duration: 0.1), value: isPlaying)
                                .disabled(globalAudioManager.playbackState == .loading)
                                
                                Button {
                                    withHapticFeedback {
                                        globalAudioManager.skipForward(themeManager.skipInterval.seconds)
                                    }
                                } label: {
                                    Image(systemName: "goforward.\(Int(themeManager.skipInterval.seconds))")
                                        .font(.title)
                                        .foregroundColor(.primaryText)
                                }
                            }
                            
                            // Speed Control with Animation
                            VStack(spacing: 12) {
                                Text(String(format: NSLocalizedString("Speed: %.1fx", comment: "Playback speed display"), playbackRate))
                                    .font(.caption)
                                    .foregroundColor(.secondaryText)
                                
                                HStack(spacing: 12) {
                                    ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                                        Button("\(String(format: "%.2fx", speed))") {
                                            withHapticFeedback {
                                                globalAudioManager.setPlaybackRate(Float(speed))
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
                        HStack(spacing: 18) {
                            ActionButton(icon: "bookmark", title: NSLocalizedString("Bookmarks", comment: "Bookmarks button title"), count: bookmarks.count) {
                                showingBookmarks = true
                            }
                            
                            ActionButton(icon: "bookmark.circle", title: NSLocalizedString("Add Bookmark", comment: "Add bookmark button title")) {
                                showingAddBookmark = true
                            }
                            
                            ActionButton(icon: "doc.text", title: NSLocalizedString("Transcript", comment: "Transcription button title")) {
                                showingTranscription = true
                            }
                            
                            if !chapters.isEmpty {
                                ActionButton(icon: "list.bullet", title: NSLocalizedString("Chapters", comment: "Chapters button title"), count: chapters.count) {
                                    showingChapterList = true
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        Spacer(minLength: 30)
                    }
                    .padding(.vertical)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            loadAudiobook()
            // Auto-play when entering the player
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if globalAudioManager.playbackState != .playing {
                    globalAudioManager.startPlayback()
                }
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if !isSeekingManually && isPlaying {
                let currentPlaybackTime = globalAudioManager.getCurrentTime()
                audiobookManager.updateProgress(for: audiobook, currentTime: currentPlaybackTime)
                statistics.addListeningTime(1, playbackRate: playbackRate)
                
                if audiobook.isFinished && !audiobook.isFinished {
                    statistics.markBookCompleted()
                }
            }
        }
        .sheet(isPresented: $showingBookmarks) {
            BookmarksView(audiobook: audiobook, globalAudioManager: globalAudioManager)
        }
        .sheet(isPresented: $showingAddBookmark) {
            AddBookmarkView(
                title: $bookmarkTitle,
                note: $bookmarkNote,
                onSave: {
                    let bookmarkTime = currentTime
                    audiobookManager.createBookmark(
                        for: audiobook,
                        at: bookmarkTime,
                        title: bookmarkTitle.isEmpty ? String(format: NSLocalizedString("Bookmark at %@", comment: "Default bookmark title with time"), formatTime(bookmarkTime)) : bookmarkTitle,
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
                    globalAudioManager.seek(to: chapter.startTime)
                    globalAudioManager.startPlayback()
                    showingChapterList = false
                }
            )
        }
        .sheet(isPresented: $showingTranscription) {
            TranscriptionView(
                audiobook: audiobook,
                currentChapterIndex: Int(currentChapter?.chapterNumber ?? 0),
                currentTime: currentTime
            )
        }
        .actionSheet(isPresented: $showingSleepTimer) {
            ActionSheet(
                title: Text(NSLocalizedString("Sleep Timer", comment: "Sleep timer action sheet title")),
                message: Text(NSLocalizedString("Choose when to stop playback", comment: "Sleep timer action sheet message")),
                buttons: [
                    .default(Text(NSLocalizedString("5 minutes", comment: "5 minute sleep timer option"))) { setSleepTimer(300) },
                    .default(Text(NSLocalizedString("10 minutes", comment: "10 minute sleep timer option"))) { setSleepTimer(600) },
                    .default(Text(NSLocalizedString("15 minutes", comment: "15 minute sleep timer option"))) { setSleepTimer(900) },
                    .default(Text(NSLocalizedString("30 minutes", comment: "30 minute sleep timer option"))) { setSleepTimer(1800) },
                    .default(Text(NSLocalizedString("End of chapter", comment: "End of chapter sleep timer option"))) { setSleepTimerEndOfChapter() },
                    .destructive(Text(NSLocalizedString("Cancel timer", comment: "Cancel sleep timer option"))) { cancelSleepTimer() },
                    .cancel()
                ]
            )
        }
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        .accentColor(themeManager.accentColor.color)
    }
    
    private func loadAudiobook() {
        globalAudioManager.loadAudiobook(audiobook)
    }
    
    private func setSleepTimer(_ seconds: TimeInterval) {
        cancelSleepTimer()
        sleepTimeRemaining = seconds
        
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            sleepTimeRemaining -= 1
            
            if sleepTimeRemaining <= 0 {
                globalAudioManager.pausePlayback()
                timer.invalidate()
                sleepTimer = nil
            }
        }
    }
    
    private func setSleepTimerEndOfChapter() {
        guard let currentChapter = currentChapter else { return }
        let currentTime = globalAudioManager.getCurrentTime()
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
    
    private func formatAccessibilityTime(_ currentTime: TimeInterval, duration: TimeInterval) -> String {
        let current = formatTime(currentTime)
        let total = formatTime(duration)
        let percentage = duration > 0 ? Int((currentTime / duration) * 100) : 0
        return String(format: NSLocalizedString("%@ of %@, %d percent complete", comment: "Accessibility description for audio progress"), current, total, percentage)
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
    @State private var seekTimer: Timer?
    @State private var pendingSeekValue: Double?
    
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
                        let newValue = range.lowerBound + localValue
                        
                        // Store the pending value and set up debounced seeking
                        pendingSeekValue = newValue
                        scheduleSeek()
                    }
                    .onEnded { _ in
                        isDragging = false
                        
                        // Cancel any pending seek timer
                        seekTimer?.invalidate()
                        seekTimer = nil
                        
                        // Perform final seek if there's a pending value
                        if let pendingValue = pendingSeekValue {
                            value = pendingValue
                            pendingSeekValue = nil
                        }
                        
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
        .onDisappear {
            // Clean up timer when view disappears
            seekTimer?.invalidate()
            seekTimer = nil
        }
    }
    
    private func scheduleSeek() {
        // Cancel previous timer
        seekTimer?.invalidate()
        
        // Use shorter debounce for better responsiveness while still preventing excessive seeks
        seekTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
            if let pendingValue = pendingSeekValue {
                value = pendingValue
                pendingSeekValue = nil
            }
        }
    }
}

#Preview {
    PlayerView(audiobook: Audiobook(), statistics: ReadingStatistics())
}
