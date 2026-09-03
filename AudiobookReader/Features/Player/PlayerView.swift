import SwiftUI
import UIKit

struct PlayerView: View {
    let audiobook: AudiobookModel
    @Environment(\.dependencies) var deps
    @State var statistics: ReadingStatistics
    @State var viewModel: PlayerViewModel

    // Access dependencies through the container
    var audioManager: any AudioManagerProtocol { deps.audioManager }
    var themeManager: ThemeManager { deps.themeManager }
    var audiobookManager: AudiobookManagerProtocol {
        deps.audiobookManager
    }

    init(audiobook: AudiobookModel, dependencies: AudiobookDependencies? = nil)
    {
        self.audiobook = audiobook
        let deps =
            dependencies
            ?? (ProcessInfo.isPreview
                ? PreviewDependencies() : LiveDependencies())
        let stats = deps.readingStatistics
        self._statistics = State(wrappedValue: stats)
        self._viewModel = State(
            wrappedValue: PlayerViewModel(
                audiobook: audiobook,
                dependencies: deps,
                statistics: stats
            )
        )
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
    @Environment(\.miniPlayerNamespace) var miniNS

    var coverImage: UIImage? {
        guard let data = audiobook.coverImageData else { return nil }
        return UIImage(data: data)
    }

    var chapters: [ChapterModel] {
        audiobook.chapters.sorted { $0.chapterNumber < $1.chapterNumber }
    }

    var bookmarks: [BookmarkModel] {
        audiobook.bookmarks.sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        GeometryReader { geometry in
            fullPlayerView(geometry: geometry)
        }
        .onAppear {
            viewModel.load()
            viewModel.autoPlayIfNeeded()
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .sheet(isPresented: $showingBookmarks) {
            BookmarksView(
                audiobook: audiobook,
                globalAudioManager: (audioManager as? GlobalAudioManager) ?? GlobalAudioManager.shared
            )
        }
        .sheet(isPresented: $showingAddBookmark) {
            AddBookmarkView(
                title: $bookmarkTitle,
                note: $bookmarkNote,
                onSave: {
                    let bookmarkTime = viewModel.currentTime
                    audiobookManager.createBookmark(
                        for: audiobook,
                        at: bookmarkTime,
                        title: bookmarkTitle.isEmpty
                            ? String(
                                format: NSLocalizedString(
                                    "Bookmark at %@",
                                    comment: "Default bookmark title with time"
                                ),
                                formatTime(bookmarkTime)
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
                onChapterTap: { chapter in
                    audioManager.seek(to: chapter.startTime)
                    audioManager.startPlayback()
                    showingChapterList = false
                }
            )
        }
        .sheet(isPresented: $showingTranscription) {
            TranscriptionView(
                audiobook: audiobook,
                currentChapterIndex: Int(
                    viewModel.currentChapter?.chapterNumber ?? 0
                ),
                currentTime: viewModel.currentTime
            )
        }
        .confirmationDialog(
            Text(
                NSLocalizedString("Sleep Timer", comment: "Sleep timer title")
            ),
            isPresented: $showingSleepTimer,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("5 minutes", comment: "Sleep timer duration option")) {
                viewModel.setSleepTimer(300)
            }
            Button(NSLocalizedString("10 minutes", comment: "Sleep timer duration option")) {
                viewModel.setSleepTimer(600)
            }
            Button(NSLocalizedString("15 minutes", comment: "Sleep timer duration option")) {
                viewModel.setSleepTimer(900)
            }
            Button(NSLocalizedString("30 minutes", comment: "Sleep timer duration option")) {
                viewModel.setSleepTimer(1800)
            }
            Button(NSLocalizedString("End of chapter", comment: "Sleep timer option: stop at end of current chapter")) {
                viewModel.setSleepTimerEndOfChapter()
            }
            Button(
                NSLocalizedString("Cancel timer", comment: "Sleep timer cancel action"),
                role: .destructive
            ) { viewModel.cancelSleepTimer() }
        }
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        .tint(themeManager.accentColor.color)
    }
}
