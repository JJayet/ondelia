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
    
}

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
}
