import SwiftUI
import UIKit

struct PlayerView: View {
    let audiobook: AudiobookModel

    // The engine is a singleton and the view reads it straight through, as `MiniPlayerBar`
    // does. Observation tracks the properties these touch, so the player redraws whenever
    // playback moves — at the engine's own tick rather than a copy on a timer.
    let audioManager = GlobalAudioManager.shared
    let themeManager = ThemeManager.shared
    let audiobookManager = AudiobookManager.shared

    /// True while the user drags the scrubber, so the position is not written back under them.
    @State var isSeekingManually = false

    var isPlaying: Bool { audioManager.playbackState == .playing }
    var currentTime: TimeInterval { audioManager.getCurrentTime() }
    var duration: TimeInterval { audioManager.getDuration() }
    var playbackRate: Float { audioManager.getPlaybackRate() }
    var sleepTimeRemaining: TimeInterval { audioManager.sleepTimeRemaining }

    var currentChapter: ChapterModel? {
        let now = currentTime
        return chapters.first { now >= $0.startTime && now < $0.endTime }
            ?? chapters.last { now >= $0.startTime }
    }

    @State var showingBookmarks = false
    @State var showingChapterList = false
    @State var showingTranscription = false
    // Sheet presentation handles dragging/dismiss. No custom drag state needed.
    @Environment(\.dismiss) var dismiss
    @Environment(\.playerRouter) var playerRouter

    var coverImage: UIImage? {
        CoverImageCache.image(for: audiobook)
    }

    var chapters: [ChapterModel] {
        audiobook.sortedChapters
    }

    var bookmarks: [BookmarkModel] {
        audiobook.bookmarks.sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        GeometryReader { geometry in
            fullPlayerView(geometry: geometry)
        }
        .onAppear {
            audioManager.loadAudiobook(audiobook)
        }
        .sheet(isPresented: $showingBookmarks) {
            BookmarksView(
                audiobook: audiobook,
                globalAudioManager: audioManager
            )
        }
        .sheet(isPresented: $showingChapterList) {
            ChapterListView(
                chapters: chapters,
                currentChapter: currentChapter,
                onChapterTap: { chapter in
                    audioManager.seek(to: chapter.startTime)
                    audioManager.startPlayback()
                    showingChapterList = false
                }
            )
        }
        .sheet(isPresented: $showingTranscription) {
            TranscriptionView(audiobook: audiobook)
        }
    }
}
