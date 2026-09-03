import Foundation
import SwiftUI
import SwiftData

// MARK: - Audio Manager Protocol
@MainActor
protocol AudioManagerProtocol: AnyObject {
    var playbackState: GlobalAudioManager.PlaybackState { get set }
    var showMiniPlayer: Bool { get set }
    var currentAudiobook: AudiobookModel? { get set }
    var isLoading: Bool { get set }
    var isReady: Bool { get set }
    
    func loadAudiobook(_ audiobook: AudiobookModel)
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

    var sleepTimeRemaining: TimeInterval { get }
    func setSleepTimer(_ seconds: TimeInterval)
    func setSleepTimerEndOfChapter()
    func cancelSleepTimer()
}

// MARK: - Theme Manager Protocol
@MainActor
protocol ThemeManagerProtocol: AnyObject {
    var currentTheme: AppTheme { get set }
    var accentColor: AccentColor { get set }
    var skipInterval: SkipInterval { get set }
    
    func setTheme(_ theme: AppTheme)
    func setAccentColor(_ color: AccentColor)
    func setSkipInterval(_ interval: SkipInterval)
}

// MARK: - Audiobook Manager Protocol
@MainActor
protocol AudiobookManagerProtocol {
    func updateProgress(for audiobook: AudiobookModel, currentTime: TimeInterval)
    func createBookmark(for audiobook: AudiobookModel, at time: TimeInterval, title: String, note: String?)
    func deleteBookmark(_ bookmark: BookmarkModel)
    func getBookmarks(for audiobook: AudiobookModel) -> [BookmarkModel]
    func markAsFinished(_ audiobook: AudiobookModel)
    func resetProgress(for audiobook: AudiobookModel)
}

// MARK: - Reading Statistics Protocol
@MainActor
protocol ReadingStatisticsProtocol: AnyObject {
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
@MainActor
protocol AudiobookDependencies {
    var audioManager: any AudioManagerProtocol { get }
    var themeManager: any ThemeManagerProtocol { get }
    var audiobookManager: AudiobookManagerProtocol { get }
    var swiftDataController: SwiftDataController { get }
    
    func createReadingStatistics() -> any ReadingStatisticsProtocol
}

// MARK: - Live Dependencies
@MainActor
class LiveDependencies: AudiobookDependencies {
    lazy var audioManager: any AudioManagerProtocol = GlobalAudioManager.shared
    lazy var themeManager: any ThemeManagerProtocol = ThemeManager.shared
    lazy var audiobookManager: AudiobookManagerProtocol = AudiobookManager.shared
    lazy var swiftDataController: SwiftDataController = SwiftDataController.shared
    private lazy var readingStatistics = ReadingStatistics.shared
    
    func createReadingStatistics() -> any ReadingStatisticsProtocol {
        return readingStatistics
    }
}

// MARK: - Preview Dependencies
@MainActor
class PreviewDependencies: AudiobookDependencies {
    lazy var audioManager: any AudioManagerProtocol = MockGlobalAudioManager()
    lazy var themeManager: any ThemeManagerProtocol = MockThemeManager()
    lazy var audiobookManager: AudiobookManagerProtocol = MockAudiobookManager()
    lazy var swiftDataController: SwiftDataController = SwiftDataController.preview
    
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
    @MainActor
    static var defaultValue: AudiobookDependencies {
        ProcessInfo.isPreview ? PreviewDependencies() : LiveDependencies()
    }
}

extension EnvironmentValues {
    var dependencies: AudiobookDependencies {
        get { self[DependencyEnvironmentKey.self] }
        set { self[DependencyEnvironmentKey.self] = newValue }
    }
}
