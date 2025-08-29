import Foundation
import SwiftUI
import CoreData

// MARK: - Mock Global Audio Manager
class MockGlobalAudioManager: AudioManagerProtocol {
    @Published var playbackState: GlobalAudioManager.PlaybackState = .stopped
    @Published var showMiniPlayer: Bool = false
    @Published var currentAudiobook: Audiobook? = nil
    @Published var isLoading: Bool = false
    @Published var isReady: Bool = true
    
    // Mock playback data
    private var mockCurrentTime: TimeInterval = 450.0 // 7:30
    private var mockDuration: TimeInterval = 3600.0 // 1 hour
    private var mockPlaybackRate: Float = 1.0
    
    func loadAudiobook(_ audiobook: Audiobook) {
        currentAudiobook = audiobook
        isReady = true
        showMiniPlayer = true
    }
    
    func startPlayback() {
        playbackState = .playing
    }
    
    func pausePlayback() {
        playbackState = .paused
    }
    
    func resumePlayback() {
        playbackState = .playing
    }
    
    func stopPlayback() {
        playbackState = .stopped
        showMiniPlayer = false
    }
    
    func togglePlayback() {
        switch playbackState {
        case .playing:
            pausePlayback()
        case .paused, .stopped:
            startPlayback()
        case .loading, .failed:
            break
        }
    }
    
    func isPlaying() -> Bool {
        return playbackState == .playing
    }
    
    func getCurrentTime() -> TimeInterval {
        return mockCurrentTime
    }
    
    func getDuration() -> TimeInterval {
        return mockDuration
    }
    
    func getPlaybackRate() -> Float {
        return mockPlaybackRate
    }
    
    func setPlaybackRate(_ rate: Float) {
        mockPlaybackRate = rate
    }
    
    func skipForward(_ seconds: TimeInterval) {
        mockCurrentTime = min(mockCurrentTime + seconds, mockDuration)
    }
    
    func skipBackward(_ seconds: TimeInterval) {
        mockCurrentTime = max(mockCurrentTime - seconds, 0)
    }
    
    func seek(to time: TimeInterval) {
        mockCurrentTime = max(0, min(time, mockDuration))
    }
    
    // Helper methods for previews
    func setMockCurrentTime(_ time: TimeInterval) {
        mockCurrentTime = time
    }
    
    func setMockDuration(_ duration: TimeInterval) {
        mockDuration = duration
    }
}

// MARK: - Mock Theme Manager
class MockThemeManager: ThemeManagerProtocol {
    @Published var currentTheme: AppTheme = .system
    @Published var accentColor: AccentColor = .blue
    @Published var skipInterval: SkipInterval = .fifteen
    @Published var autoPlay: Bool = true
    
    func setTheme(_ theme: AppTheme) {
        currentTheme = theme
    }
    
    func setAccentColor(_ color: AccentColor) {
        accentColor = color
    }
    
    func setSkipInterval(_ interval: SkipInterval) {
        skipInterval = interval
    }
}

// MARK: - Mock Audiobook Manager
class MockAudiobookManager: AudiobookManagerProtocol {
    private var mockBookmarks: [String: [MockBookmark]] = [:]
    
    struct MockBookmark {
        let id: UUID = UUID()
        let timestamp: TimeInterval
        let title: String
        let note: String?
    }
    
    func updateProgress(for audiobook: Audiobook, currentTime: TimeInterval) {
        // Mock implementation - in real app this would update Core Data
        audiobook.currentPosition = currentTime
    }
    
    func createBookmark(for audiobook: Audiobook, at time: TimeInterval, title: String, note: String?) {
        let bookmarkKey = audiobook.id?.uuidString ?? "unknown"
        let bookmark = MockBookmark(timestamp: time, title: title, note: note)
        
        if mockBookmarks[bookmarkKey] == nil {
            mockBookmarks[bookmarkKey] = []
        }
        mockBookmarks[bookmarkKey]?.append(bookmark)
    }
    
    func deleteBookmark(_ bookmark: Bookmark) {
        // Mock implementation
    }
    
    func getBookmarks(for audiobook: Audiobook) -> [Bookmark] {
        // Mock implementation - return empty array for previews
        return []
    }
    
    func markAsFinished(_ audiobook: Audiobook) {
        audiobook.isFinished = true
    }
    
    func resetProgress(for audiobook: Audiobook) {
        audiobook.currentPosition = 0
        audiobook.isFinished = false
    }
}

// MARK: - Mock Reading Statistics
class MockReadingStatistics: ReadingStatisticsProtocol {
    @Published var totalListeningTime: TimeInterval = 125400.0 // ~34.8 hours
    @Published var booksCompleted: Int = 12
    @Published var currentStreak: Int = 7
    @Published var averageSpeed: Float = 1.3
    
    func addListeningTime(_ time: TimeInterval, playbackRate: Float) {
        totalListeningTime += time
        // Update average speed calculation
        let weightedSpeed = (averageSpeed * 0.95) + (playbackRate * 0.05)
        averageSpeed = weightedSpeed
    }
    
    func markBookCompleted() {
        booksCompleted += 1
        currentStreak += 1
    }
    
    func updateStreak() {
        // Mock streak calculation
    }
    
    func getAverageSpeed() -> Float {
        return averageSpeed
    }
}

// MARK: - Core Data Extensions for Previews
extension Audiobook {
    static func preview(
        title: String = "The Art of War",
        author: String = "Sun Tzu", 
        narrator: String = "Derek Jacobi",
        duration: TimeInterval = 3600.0,
        currentPosition: TimeInterval = 450.0,
        isFinished: Bool = false
    ) -> Audiobook {
        let context = PersistenceController.preview.container.viewContext
        let audiobook = Audiobook(context: context)
        
        audiobook.id = UUID()
        audiobook.title = title
        audiobook.author = author
        audiobook.narrator = narrator
        audiobook.duration = duration
        audiobook.currentPosition = currentPosition
        audiobook.isFinished = isFinished
        
        // Create mock cover image data
        if let mockImage = createMockCoverImage(title: title) {
            audiobook.coverImageData = mockImage
        }
        
        // Create sample chapters
        let chapter1 = Chapter(context: context)
        chapter1.id = UUID()
        chapter1.title = "Chapter 1: Introduction"
        chapter1.chapterNumber = 1
        chapter1.startTime = 0
        chapter1.endTime = 1800
        chapter1.audiobook = audiobook
        
        let chapter2 = Chapter(context: context)
        chapter2.id = UUID()
        chapter2.title = "Chapter 2: Planning"
        chapter2.chapterNumber = 2
        chapter2.startTime = 1800
        chapter2.endTime = 3600
        chapter2.audiobook = audiobook
        
        return audiobook
    }
    
    private static func createMockCoverImage(title: String) -> Data? {
        let size = CGSize(width: 300, height: 300)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let image = renderer.image { context in
            // Create gradient background
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                    colors: [UIColor.systemBlue.cgColor, UIColor.systemPurple.cgColor] as CFArray,
                                    locations: [0.0, 1.0])!
            
            context.cgContext.drawLinearGradient(gradient,
                                               start: CGPoint(x: 0, y: 0),
                                               end: CGPoint(x: size.width, y: size.height),
                                               options: [])
            
            // Add book icon
            let bookIcon = UIImage(systemName: "book.closed.fill")
            let iconSize = CGSize(width: 80, height: 80)
            let iconRect = CGRect(x: (size.width - iconSize.width) / 2,
                                y: (size.height - iconSize.height) / 2 - 20,
                                width: iconSize.width,
                                height: iconSize.height)
            
            bookIcon?.withTintColor(.white).draw(in: iconRect)
            
            // Add title text
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .medium),
                .foregroundColor: UIColor.white
            ]
            
            let titleSize = title.size(withAttributes: attributes)
            let titleRect = CGRect(x: (size.width - titleSize.width) / 2,
                                 y: iconRect.maxY + 10,
                                 width: titleSize.width,
                                 height: titleSize.height)
            
            title.draw(in: titleRect, withAttributes: attributes)
        }
        
        return image.pngData()
    }
}

extension Chapter {
    static func preview(
        title: String = "Chapter 1: Introduction",
        chapterNumber: Int = 1,
        startTime: TimeInterval = 0,
        endTime: TimeInterval = 1800
    ) -> Chapter {
        let context = PersistenceController.preview.container.viewContext
        let chapter = Chapter(context: context)
        
        chapter.id = UUID()
        chapter.title = title
        chapter.chapterNumber = Int16(chapterNumber)
        chapter.startTime = startTime
        chapter.endTime = endTime
        
        return chapter
    }
}

extension Bookmark {
    static func preview(
        title: String = "Important Quote",
        note: String? = "This is a really insightful passage",
        timestamp: TimeInterval = 300.0
    ) -> Bookmark {
        let context = PersistenceController.preview.container.viewContext
        let bookmark = Bookmark(context: context)
        
        bookmark.id = UUID()
        bookmark.title = title
        bookmark.note = note
        bookmark.timestamp = timestamp
        
        return bookmark
    }
}