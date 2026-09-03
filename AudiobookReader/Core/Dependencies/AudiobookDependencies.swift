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

// MARK: - Dependency Container
@MainActor
protocol AudiobookDependencies {
    var audioManager: any AudioManagerProtocol { get }
    var audiobookManager: AudiobookManagerProtocol { get }
    var themeManager: ThemeManager { get }
    var readingStatistics: ReadingStatistics { get }
    var swiftDataController: SwiftDataController { get }
}

// MARK: - Live Dependencies
@MainActor
class LiveDependencies: AudiobookDependencies {
    nonisolated init() {}

    lazy var audioManager: any AudioManagerProtocol = GlobalAudioManager.shared
    lazy var audiobookManager: AudiobookManagerProtocol = AudiobookManager.shared
    lazy var themeManager: ThemeManager = .shared
    lazy var readingStatistics: ReadingStatistics = .shared
    lazy var swiftDataController: SwiftDataController = SwiftDataController.shared
}

// MARK: - Preview Dependencies
@MainActor
class PreviewDependencies: AudiobookDependencies {
    nonisolated init() {}

    // Audio and library are mocked so a preview never touches real playback or the store.
    // Theme and statistics are cheap value holders, so previews use fresh real ones.
    lazy var audioManager: any AudioManagerProtocol = MockGlobalAudioManager()
    lazy var audiobookManager: AudiobookManagerProtocol = MockAudiobookManager()
    lazy var themeManager: ThemeManager = .shared
    lazy var readingStatistics = ReadingStatistics()
    lazy var swiftDataController: SwiftDataController = SwiftDataController.preview
}

// MARK: - Environment Detection
extension ProcessInfo {
    static var isPreview: Bool {
        processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}

// MARK: - Environment Key
extension EnvironmentValues {
    @Entry var dependencies: AudiobookDependencies =
        ProcessInfo.isPreview ? PreviewDependencies() : LiveDependencies()
}
