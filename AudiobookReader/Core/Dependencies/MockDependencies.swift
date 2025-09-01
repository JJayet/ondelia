import Foundation
import SwiftUI
import SwiftData

// MARK: - Mock Global Audio Manager
class MockGlobalAudioManager: AudioManagerProtocol {
    @Published var playbackState: GlobalAudioManager.PlaybackState = .stopped
    @Published var showMiniPlayer: Bool = false
    @Published var currentAudiobook: AudiobookModel? = nil
    @Published var isLoading: Bool = false
    @Published var isReady: Bool = true
    
    // Mock playback data
    private var mockCurrentTime: TimeInterval = 450.0 // 7:30
    private var mockDuration: TimeInterval = 3600.0 // 1 hour
    private var mockPlaybackRate: Float = 1.0
    
    func loadAudiobook(_ audiobook: AudiobookModel) {
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
    
    func updateProgress(for audiobook: AudiobookModel, currentTime: TimeInterval) {
        // Mock implementation - in real app this would update SwiftData
        audiobook.currentPosition = currentTime
    }
    
    func createBookmark(for audiobook: AudiobookModel, at time: TimeInterval, title: String, note: String?) {
        let bookmarkKey = audiobook.id.uuidString
        let bookmark = MockBookmark(timestamp: time, title: title, note: note)
        
        if mockBookmarks[bookmarkKey] == nil {
            mockBookmarks[bookmarkKey] = []
        }
        mockBookmarks[bookmarkKey]?.append(bookmark)
    }
    
    func deleteBookmark(_ bookmark: BookmarkModel) {
        // Mock implementation
    }
    
    func getBookmarks(for audiobook: AudiobookModel) -> [BookmarkModel] {
        // Mock implementation - return empty array for previews
        return []
    }
    
    func markAsFinished(_ audiobook: AudiobookModel) {
        audiobook.isFinished = true
    }
    
    func resetProgress(for audiobook: AudiobookModel) {
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
extension AudiobookModel {
    static func preview(
        title: String = "The Art of War",
        author: String = "Sun Tzu", 
        narrator: String = "Derek Jacobi",
        duration: TimeInterval = 3600.0,
        currentPosition: TimeInterval = 450.0,
        isFinished: Bool = false
    ) -> AudiobookModel {
        let audiobook = AudiobookModel(
            title: title,
            author: author,
            narrator: narrator,
            duration: duration,
            currentPosition: currentPosition,
            isFinished: isFinished,
            dateAdded: Date(),
            lastPlayed: Date().addingTimeInterval(-3600)
        )
        
        // Create mock cover image data
        if let mockImage = createMockCoverImage(title: title) {
            audiobook.coverImageData = mockImage
        }
        
        // Create sample chapters
        let chapter1 = ChapterModel(
            title: "Chapter 1: Introduction",
            chapterNumber: 1,
            startTime: 0,
            endTime: 1800
        )
        chapter1.audiobook = audiobook
        
        let chapter2 = ChapterModel(
            title: "Chapter 2: Planning",
            chapterNumber: 2,
            startTime: 1800,
            endTime: 3600
        )
        chapter2.audiobook = audiobook
        
        audiobook.chapters = [chapter1, chapter2]
        
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

extension ChapterModel {
    static func preview(
        title: String = "Chapter 1: Introduction",
        chapterNumber: Int = 1,
        startTime: TimeInterval = 0,
        endTime: TimeInterval = 1800
    ) -> ChapterModel {
        return ChapterModel(
            title: title,
            chapterNumber: Int16(chapterNumber),
            startTime: startTime,
            endTime: endTime
        )
    }
}

extension BookmarkModel {
    static func preview(
        title: String = "Important Quote",
        note: String? = "This is a really insightful passage",
        timestamp: TimeInterval = 300.0
    ) -> BookmarkModel {
        return BookmarkModel(
            title: title,
            note: note,
            timestamp: timestamp,
            dateCreated: Date()
        )
    }
}