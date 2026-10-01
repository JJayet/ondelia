import SwiftUI
import TipKit
import UIKit

struct PlayerView: View {
    /// The book this screen was opened on. Playback can move past it — the end of a book rolls
    /// into the next one — so the screen follows whatever the engine holds, not this.
    let openedBook: AudiobookModel
    /// Shown as the Now Playing pane beside the sidebar: the tab accessory is the transport and
    /// there is nothing to close, so the bottom bar and the close button stay out.
    var embedded = false

    var audiobook: AudiobookModel { audioManager.currentAudiobook ?? openedBook }

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
    @State var showingQueue = false
    // Sheet presentation handles dragging/dismiss. No custom drag state needed.
    @Environment(\.dismiss) var dismiss
    @Environment(\.playerRouter) var playerRouter
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

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
        // The room is the blurred cover under a black gradient whatever the theme, so the
        // player's type is always light-on-dark; in the light theme `.secondary` vanished.
        .environment(\.colorScheme, .dark)
        .onAppear {
            audioManager.loadAudiobook(openedBook)
            Task { await AppTips.playerOpened.donate() }
        }
        .onChange(of: nextEntry?.id, initial: true) { _, id in
            QueueTip.hasNext = id != nil
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
        .sheet(isPresented: $showingQueue) {
            PlayQueueView(chained: audiobookManager.nextEntry(after: audiobook)) { book in
                audioManager.loadAudiobook(book)
                audioManager.startPlaybackAfterOpeningBook()
                PlayQueue.shared.remove(book)
            }
        }
    }
}
