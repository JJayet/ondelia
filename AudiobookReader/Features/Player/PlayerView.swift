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
    /// Remembered: whoever wants time-left wants it every time.
    @AppStorage("player.showRemainingTime") var showRemainingTime = false

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
    @State var showingAddBookmark = false
    @State var showingSleepTimer = false
    @State var showingChapterList = false
    @State var showingTranscription = false
    @State var bookmarkTitle = ""
    @State var bookmarkNote = ""
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
        .sheet(isPresented: $showingAddBookmark) {
            AddBookmarkView(
                title: $bookmarkTitle,
                note: $bookmarkNote,
                onSave: {
                    let bookmarkTime = currentTime
                    audiobookManager.createBookmark(
                        for: audiobook,
                        at: bookmarkTime,
                        title: bookmarkTitle.isEmpty
                            ? String(
                                format: NSLocalizedString(
                                    "Bookmark at %@",
                                    comment: "Default bookmark title with time"
                                ),
                                bookmarkTime.clockFormatted
                            ) : bookmarkTitle,
                        note: bookmarkNote.isEmpty ? nil : bookmarkNote
                    )
                    bookmarkTitle = ""
                    bookmarkNote = ""
                }
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
        .confirmationDialog(
            Text(
                NSLocalizedString("Sleep Timer", comment: "Sleep timer title")
            ),
            isPresented: $showingSleepTimer,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("5 minutes", comment: "Sleep timer duration option")) {
                audioManager.setSleepTimer(300)
            }
            Button(NSLocalizedString("10 minutes", comment: "Sleep timer duration option")) {
                audioManager.setSleepTimer(600)
            }
            Button(NSLocalizedString("15 minutes", comment: "Sleep timer duration option")) {
                audioManager.setSleepTimer(900)
            }
            Button(NSLocalizedString("30 minutes", comment: "Sleep timer duration option")) {
                audioManager.setSleepTimer(1800)
            }
            Button(NSLocalizedString("45 minutes", comment: "Sleep timer duration option")) {
                audioManager.setSleepTimer(2700)
            }
            Button(NSLocalizedString("60 minutes", comment: "Sleep timer duration option")) {
                audioManager.setSleepTimer(3600)
            }
            Button(NSLocalizedString("End of chapter", comment: "Sleep timer option: stop at end of current chapter")) {
                audioManager.setSleepTimerEndOfChapter()
            }
            Button(
                NSLocalizedString("Cancel timer", comment: "Sleep timer cancel action"),
                role: .destructive
            ) { audioManager.cancelSleepTimer() }
        }
    }
}
