import Foundation
import SwiftUI
import SwiftData

// MARK: - Mock Global Audio Manager
@MainActor
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

    var sleepTimeRemaining: TimeInterval = 0
    func setSleepTimer(_ seconds: TimeInterval) { sleepTimeRemaining = seconds }
    func setSleepTimerEndOfChapter() { sleepTimeRemaining = 60 }
    func cancelSleepTimer() { sleepTimeRemaining = 0 }
    
    // Helper methods for previews
    func setMockCurrentTime(_ time: TimeInterval) {
        mockCurrentTime = time
    }
    
    func setMockDuration(_ duration: TimeInterval) {
        mockDuration = duration
    }
}

// MARK: - Mock Theme Manager
@MainActor
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
@MainActor
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
@MainActor
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
