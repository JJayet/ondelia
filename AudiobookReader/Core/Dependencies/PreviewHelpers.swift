import SwiftUI

// MARK: - Preview Wrapper
@MainActor
struct PreviewWrapper<Content: View>: View {
    let content: Content
    let customDependencies: AudiobookDependencies?
    
    init(dependencies: AudiobookDependencies? = nil, @ViewBuilder content: () -> Content) {
        self.customDependencies = dependencies
        self.content = content()
    }
    
    var body: some View {
        let deps = customDependencies ?? PreviewDependencies()
        
        content
            .environment(\.dependencies, deps)
            .modelContainer(deps.swiftDataController.container)
    }
}

// MARK: - View Extension for Preview Dependencies
@MainActor
extension View {
    func previewDependencies(_ dependencies: AudiobookDependencies? = nil) -> some View {
        PreviewWrapper(dependencies: dependencies) {
            self
        }
    }
    
    func previewWithMockAudio(
        state: GlobalAudioManager.PlaybackState = .playing,
        currentTime: TimeInterval = 450.0,
        duration: TimeInterval = 3600.0,
        showMiniPlayer: Bool = true
    ) -> some View {
        let deps = PreviewDependencies()
        
        let mockAudio = deps.audioManager as! MockGlobalAudioManager
        
        mockAudio.currentAudiobook = PreviewContent.audiobookLong()
        mockAudio.playbackState = state
        mockAudio.setMockCurrentTime(currentTime)
        mockAudio.setMockDuration(duration)
        mockAudio.showMiniPlayer = showMiniPlayer
        
        return PreviewWrapper(dependencies: deps) {
            self
        }
    }
    
    func previewWithTheme(
        theme: AppTheme = .system,
        accentColor: AccentColor = .blue
    ) -> some View {
        let deps = PreviewDependencies()
        let mockTheme = deps.themeManager as! MockThemeManager
        
        mockTheme.currentTheme = theme
        mockTheme.accentColor = accentColor
        
        return PreviewWrapper(dependencies: deps) {
            self
        }
    }
}

// MARK: - Preview State Configurator
@MainActor
class PreviewStateConfigurator {
    private let dependencies = PreviewDependencies()
    
    var audioManager: MockGlobalAudioManager {
        return dependencies.audioManager as! MockGlobalAudioManager
    }
    
    var themeManager: MockThemeManager {
        return dependencies.themeManager as! MockThemeManager
    }
    
    var audiobookManager: MockAudiobookManager {
        return dependencies.audiobookManager as! MockAudiobookManager
    }
    
    func configurePlaybackState(_ state: GlobalAudioManager.PlaybackState) -> PreviewStateConfigurator {
        audioManager.playbackState = state
        return self
    }
    
    func configureCurrentTime(_ time: TimeInterval) -> PreviewStateConfigurator {
        audioManager.setMockCurrentTime(time)
        return self
    }
    
    func configureDuration(_ duration: TimeInterval) -> PreviewStateConfigurator {
        audioManager.setMockDuration(duration)
        return self
    }
    
    func configureTheme(_ theme: AppTheme) -> PreviewStateConfigurator {
        themeManager.currentTheme = theme
        return self
    }
    
    func configureAccentColor(_ color: AccentColor) -> PreviewStateConfigurator {
        themeManager.accentColor = color
        return self
    }
    
    func configureMiniPlayer(show: Bool) -> PreviewStateConfigurator {
        audioManager.showMiniPlayer = show
        return self
    }
    
    func build() -> AudiobookDependencies {
        return dependencies
    }
}

// MARK: - Preview Content Factory
struct PreviewContent {
    static func audiobook(
        title: String = "The Art of War",
        author: String = "Sun Tzu",
        narrator: String = "Derek Jacobi"
    ) -> AudiobookModel {
        return AudiobookModel(
            title: title,
            author: author,
            narrator: narrator,
            duration: 3600.0,
            currentPosition: 450.0,
            dateAdded: Date()
        )
    }
    
    static func audiobookLong() -> AudiobookModel {
        return AudiobookModel(
            title: "A Really Long Audiobook Title That Might Wrap to Multiple Lines",
            author: "An Author With a Very Long Name That Tests Layout",
            narrator: "A Narrator With an Even Longer Name For Testing",
            duration: 12600.0, // 3.5 hours
            currentPosition: 3780.0, // 1 hour 3 minutes
            dateAdded: Date()
        )
    }
    
    static func audiobookFinished() -> AudiobookModel {
        let audiobook = AudiobookModel(
            title: "Completed Book",
            author: "Test Author",
            duration: 3600.0,
            currentPosition: 3600.0,
            isFinished: true,
            dateAdded: Date(),
        )
        audiobook.bookmarks = [bookmark()]
        return audiobook
    }
    
    static func chapter(
        title: String = "Chapter 1: Introduction",
        number: Int = 1
    ) -> ChapterModel {
        return ChapterModel(
            title: title,
            chapterNumber: Int16(number),
            startTime: 0.0,
            endTime: 300.0
        )
    }
    
    static func bookmark(
        title: String = "Important Quote",
        note: String? = "This is insightful"
    ) -> BookmarkModel {
        return BookmarkModel(
            title: title,
            note: note,
            timestamp: 450.0,
            dateCreated: Date()
        )
    }
    
    @MainActor static func readingStatistics() -> any ReadingStatisticsProtocol {
        return MockReadingStatistics()
    }
}

// MARK: - Preview Device Configurations
extension PreviewDevice {
    static let iPhone16 = PreviewDevice(rawValue: "iPhone 16")
    static let iPhone16Pro = PreviewDevice(rawValue: "iPhone 16 Pro")
    static let iPhone16Plus = PreviewDevice(rawValue: "iPhone 16 Plus")
    static let iPhone16ProMax = PreviewDevice(rawValue: "iPhone 16 Pro Max")
}

// MARK: - Common Preview Configurations
extension View {
    func previewAllDevices() -> some View {
        Group {
            self.previewDevice(.iPhone16)
                .previewDisplayName("iPhone 16")
            
            self.previewDevice(.iPhone16Pro)
                .previewDisplayName("iPhone 16 Pro")
            
            self.previewDevice(.iPhone16Plus)
                .previewDisplayName("iPhone 16 Plus")
        }
        .previewDependencies()
    }
    
    func previewAllStates() -> some View {
        Group {
            self.previewWithMockAudio(state: .playing)
                .previewDisplayName("Playing")
            
            self.previewWithMockAudio(state: .paused)
                .previewDisplayName("Paused")
            
            self.previewWithMockAudio(state: .loading)
                .previewDisplayName("Loading")
            
            self.previewWithMockAudio(state: .stopped, showMiniPlayer: false)
                .previewDisplayName("Stopped")
        }
    }
    
    func previewAllThemes() -> some View {
        Group {
            self.previewWithTheme(theme: .light, accentColor: .blue)
                .previewDisplayName("Light Theme")
            
            self.previewWithTheme(theme: .dark, accentColor: .purple)
                .previewDisplayName("Dark Theme")
            
            self.previewWithTheme(theme: .system, accentColor: .green)
                .previewDisplayName("System Theme")
        }
    }
}
