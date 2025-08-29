import Foundation
import SwiftUI
import CoreData

// MARK: - Audio Manager Protocol
protocol AudioManagerProtocol: ObservableObject {
    var playbackState: GlobalAudioManager.PlaybackState { get set }
    var showMiniPlayer: Bool { get set }
    var currentAudiobook: Audiobook? { get set }
    var isLoading: Bool { get set }
    var isReady: Bool { get set }
    
    func loadAudiobook(_ audiobook: Audiobook)
    func startPlayback()
    func pausePlayback()
    func resumePlayback()
    func stopPlayback()
    func togglePlayback()
    func isPlaying() -> Bool
    func getCurrentTime() -> TimeInterval
    func getDuration() -> TimeInterval
    func getPlaybackRate() -> Float
    func setPlaybackRate(_ rate: Float)
    func skipForward(_ seconds: TimeInterval)
    func skipBackward(_ seconds: TimeInterval)
    func seek(to time: TimeInterval)
}

// MARK: - Theme Manager Protocol
protocol ThemeManagerProtocol: ObservableObject {
    var currentTheme: AppTheme { get set }
    var accentColor: AccentColor { get set }
    var skipInterval: SkipInterval { get set }
    
    func setTheme(_ theme: AppTheme)
    func setAccentColor(_ color: AccentColor)
    func setSkipInterval(_ interval: SkipInterval)
}

// MARK: - Audiobook Manager Protocol
protocol AudiobookManagerProtocol {
    func updateProgress(for audiobook: Audiobook, currentTime: TimeInterval)
    func createBookmark(for audiobook: Audiobook, at time: TimeInterval, title: String, note: String?)
    func deleteBookmark(_ bookmark: Bookmark)
    func getBookmarks(for audiobook: Audiobook) -> [Bookmark]
    func markAsFinished(_ audiobook: Audiobook)
    func resetProgress(for audiobook: Audiobook)
}

// MARK: - Reading Statistics Protocol
protocol ReadingStatisticsProtocol: ObservableObject {
    var totalListeningTime: TimeInterval { get set }
    var booksCompleted: Int { get set }
    var currentStreak: Int { get set }
    var averageSpeed: Float { get set }
    
    func addListeningTime(_ time: TimeInterval, playbackRate: Float)
    func markBookCompleted()
    func updateStreak()
    func getAverageSpeed() -> Float
}

// MARK: - Dependency Container
protocol AudiobookDependencies {
    var audioManager: any AudioManagerProtocol { get }
    var themeManager: any ThemeManagerProtocol { get }
    var audiobookManager: AudiobookManagerProtocol { get }
    var persistenceController: PersistenceController { get }
    
    func createReadingStatistics() -> any ReadingStatisticsProtocol
}

// MARK: - Live Dependencies
class LiveDependencies: AudiobookDependencies {
    lazy var audioManager: any AudioManagerProtocol = GlobalAudioManager.shared
    lazy var themeManager: any ThemeManagerProtocol = ThemeManager.shared
    lazy var audiobookManager: AudiobookManagerProtocol = AudiobookManager()
    lazy var persistenceController: PersistenceController = PersistenceController.shared
    
    func createReadingStatistics() -> any ReadingStatisticsProtocol {
        return ReadingStatistics()
    }
}

// MARK: - Preview Dependencies
class PreviewDependencies: AudiobookDependencies {
    lazy var audioManager: any AudioManagerProtocol = MockGlobalAudioManager()
    lazy var themeManager: any ThemeManagerProtocol = MockThemeManager()
    lazy var audiobookManager: AudiobookManagerProtocol = MockAudiobookManager()
    lazy var persistenceController: PersistenceController = PersistenceController.preview
    
    func createReadingStatistics() -> any ReadingStatisticsProtocol {
        return MockReadingStatistics()
    }
}

// MARK: - Environment Detection
extension ProcessInfo {
    static var isPreview: Bool {
        processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}

// MARK: - Environment Key
private struct DependencyEnvironmentKey: EnvironmentKey {
    static let defaultValue: AudiobookDependencies = ProcessInfo.isPreview ? 
        PreviewDependencies() : LiveDependencies()
}

extension EnvironmentValues {
    var dependencies: AudiobookDependencies {
        get { self[DependencyEnvironmentKey.self] }
        set { self[DependencyEnvironmentKey.self] = newValue }
    }
}
