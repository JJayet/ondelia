import SwiftUI
import UIKit

struct PlayerView: View {
    let audiobook: AudiobookModel
    @Environment(\.dependencies) private var deps
    @StateObject private var statistics: ReadingStatistics
    @StateObject private var viewModel: PlayerViewModel

    // Access dependencies through the container
    private var audioManager: any AudioManagerProtocol { deps.audioManager }
    private var themeManager: any ThemeManagerProtocol { deps.themeManager }
    private var audiobookManager: AudiobookManagerProtocol {
        deps.audiobookManager
    }

    init(audiobook: AudiobookModel, dependencies: AudiobookDependencies? = nil)
    {
        self.audiobook = audiobook
        let deps =
            dependencies
            ?? (ProcessInfo.isPreview
                ? PreviewDependencies() : LiveDependencies())
        let stats = deps.createReadingStatistics() as! ReadingStatistics
        self._statistics = StateObject(wrappedValue: stats)
        self._viewModel = StateObject(
            wrappedValue: PlayerViewModel(
                audiobook: audiobook,
                dependencies: deps,
                statistics: stats
            )
        )
    }

    @State private var showingBookmarks = false
    @State private var showingAddBookmark = false
    @State private var showingSleepTimer = false
    @State private var showingChapterList = false
    @State private var showingTranscription = false
    @State private var bookmarkTitle = ""
    @State private var bookmarkNote = ""
    // Sheet presentation handles dragging/dismiss. No custom drag state needed.
    @Environment(\.dismiss) private var dismiss
    @Environment(\.playerRouter) private var playerRouter
    @Environment(\.miniPlayerNamespace) private var miniNS

    private var coverImage: UIImage? {
        guard let data = audiobook.coverImageData else { return nil }
        return UIImage(data: data)
    }

    private var chapters: [ChapterModel] {
        audiobook.chapters.sorted { $0.chapterNumber < $1.chapterNumber }
    }

    private var bookmarks: [BookmarkModel] {
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
                globalAudioManager: audioManager as! GlobalAudioManager
            )
        }
        .sheet(isPresented: $showingAddBookmark) {
            AddBookmarkView(
                title: $bookmarkTitle,
                note: $bookmarkNote,
                onSave: {
                    let bookmarkTime = viewModel.currentTime  // Use @Published property directly
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
                currentTime: viewModel.currentTime  // Use @Published property directly
            )
        }
        .confirmationDialog(
            Text(
                NSLocalizedString("Sleep Timer", comment: "Sleep timer title")
            ),
            isPresented: $showingSleepTimer,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("5 minutes", comment: "")) {
                viewModel.setSleepTimer(300)
            }
            Button(NSLocalizedString("10 minutes", comment: "")) {
                viewModel.setSleepTimer(600)
            }
            Button(NSLocalizedString("15 minutes", comment: "")) {
                viewModel.setSleepTimer(900)
            }
            Button(NSLocalizedString("30 minutes", comment: "")) {
                viewModel.setSleepTimer(1800)
            }
            Button(NSLocalizedString("End of chapter", comment: "")) {
                viewModel.setSleepTimerEndOfChapter(
                    currentChapter: viewModel.currentChapter,
                    currentTime: viewModel.currentTime
                )  // Use @Published property directly
            }
            Button(
                NSLocalizedString("Cancel timer", comment: ""),
                role: .destructive
            ) { viewModel.cancelSleepTimer() }
        }
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        .tint(themeManager.accentColor.color)
    }

    // MARK: - Full Player View
    @ViewBuilder
    private func fullPlayerView(geometry: GeometryProxy) -> some View {
        ZStack {
            // Background layer - full screen with cover image
            backgroundLayer(geometry: geometry)
            VStack {
                Spacer()
                controlPanel
                    .frame(height: geometry.size.height * 0.7)  // 70% height
            }
        }
    }

    // Mini player UI is handled by the tabViewBottomAccessory
    // MARK: - Background Layer
    @ViewBuilder
    private func backgroundLayer(geometry: GeometryProxy) -> some View {
        if let coverImage = coverImage {
            Image(uiImage: coverImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height,
                    alignment: .top
                )
                .clipped()
        } else {
            // Fallback gradient background
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.6),
                    Color.primaryBackground,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    // MARK: - Control Panel
    @ViewBuilder
    private var controlPanel: some View {
        VStack(spacing: 20) {
            headerControls

            Spacer()

            bookInfo

            progressSection

            actionButtons

            Spacer()
        }
        .padding(.horizontal, 16)
        .glassEffect(
            .regular.interactive(),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Header Controls
    @ViewBuilder
    private var headerControls: some View {
        HStack {
            Button {
                // Dismiss overlay by clearing router's presented
                if let router = playerRouter {
                    router.presented = nil
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title2)
                    .foregroundColor(.primaryText)
            }

            Spacer()

            Button {
                showingSleepTimer = true
            } label: {
                if viewModel.sleepTimeRemaining > 0 {
                    Label(
                        formatTime(viewModel.sleepTimeRemaining),
                        systemImage: "moon.fill"
                    )
                    .font(.caption)
                    .foregroundColor(.accentColor)
                } else {
                    Image(systemName: "moon")
                        .font(.title2)
                        .foregroundColor(.primaryText)
                }
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Book Info
    @ViewBuilder
    private var bookInfo: some View {
        VStack(spacing: 8) {
            Text(
                audiobook.title
                    ?? NSLocalizedString(
                        "Unknown Title",
                        comment: "Default title for audiobooks without title"
                    )
            )
            .font(.title2)
            .foregroundColor(.primaryText)
            .multilineTextAlignment(.center)
            .lineLimit(2)

            Text(
                audiobook.author
                    ?? NSLocalizedString(
                        "Unknown Author",
                        comment: "Default author for audiobooks without author"
                    )
            )
            .font(.headline)
            .foregroundColor(.secondaryText)

            if let narrator = audiobook.narrator {
                Text(
                    String(
                        format: NSLocalizedString(
                            "Narrated by %@",
                            comment: "Narrator credit text"
                        ),
                        narrator
                    )
                )
                .font(.subheadline)
                .foregroundColor(.secondaryText)
            }

            // Current Chapter
            if let chapter = viewModel.currentChapter {
                Text(
                    chapter.title
                        ?? String(
                            format: NSLocalizedString(
                                "Chapter %d",
                                comment: "Default chapter title with number"
                            ),
                            chapter.chapterNumber
                        )
                )
                .font(.footnote)
                .foregroundColor(.accentColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassEffect(
                    .regular.interactive(),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }
        }
    }

    // MARK: - Progress Section
    @ViewBuilder
    private var progressSection: some View {
        VStack(spacing: 16) {
            // Time Slider
            progressSlider

            // Playback controls
            playbackControls

            // Speed control
            speedControls
        }
    }

    // MARK: - Progress Slider
    @ViewBuilder
    private var progressSlider: some View {
        VStack(spacing: 8) {
            PlayerProgressSlider(
                value: Binding(
                    get: { viewModel.currentTime },  // Use @Published property directly
                    set: { newValue in
                        audioManager.seek(to: newValue)
                    }
                ),
                range: 0...max(viewModel.duration, 1),  // Use @Published property directly
                onEditingChanged: { editing in
                    viewModel.isSeekingManually = editing
                }
            )

            HStack {
                Text(formatTime(viewModel.currentTime))  // Use @Published property directly
                    .font(.caption)
                    .foregroundColor(.secondaryText)
                    .monospacedDigit()

                Spacer()

                Text(formatTime(viewModel.duration))  // Use @Published property directly
                    .font(.caption)
                    .foregroundColor(.secondaryText)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Playback Controls
    @ViewBuilder
    private var playbackControls: some View {
        HStack(spacing: 40) {
            Button {
                let skipInterval = themeManager.skipInterval.seconds
                withHapticFeedback {
                    DispatchQueue.main.async {
                        audioManager.skipBackward(skipInterval)
                    }
                }
            } label: {
                Image(
                    systemName:
                        "gobackward.\(Int(themeManager.skipInterval.seconds))"
                )
                .font(.title)
                .foregroundColor(.primaryText)
            }

            Button {
                withHapticFeedback(.medium) {
                    DispatchQueue.main.async {
                        if audioManager.playbackState != .loading {
                            audioManager.togglePlayback()
                        }
                    }
                }
            } label: {
                Group {
                    if audioManager.playbackState == .loading {
                        ProgressView()
                            .scaleEffect(1.8)
                            .progressViewStyle(
                                CircularProgressViewStyle(tint: .accentColor)
                            )
                    } else {
                        Image(
                            systemName: viewModel.isPlaying
                                ? "pause.circle.fill" : "play.circle.fill"
                        )  // Use @Published property directly
                        .font(.system(size: 80))
                        .foregroundColor(.accentColor)
                        .shadow(
                            color: .accentColor.opacity(0.3),
                            radius: 8,
                            x: 0,
                            y: 4
                        )
                    }
                }
            }
            .frame(width: 80, height: 80)
            .disabled(audioManager.playbackState == .loading)

            Button {
                let skipInterval = themeManager.skipInterval.seconds
                withHapticFeedback {
                    DispatchQueue.main.async {
                        audioManager.skipForward(skipInterval)
                    }
                }
            } label: {
                Image(
                    systemName:
                        "goforward.\(Int(themeManager.skipInterval.seconds))"
                )
                .font(.title)
                .foregroundColor(.primaryText)
            }
        }
    }

    // MARK: - Speed Controls
    @ViewBuilder
    private var speedControls: some View {
        VStack(spacing: 12) {
            Text(
                String(
                    format: NSLocalizedString(
                        "Speed: %.1fx",
                        comment: "Playback speed display"
                    ),
                    viewModel.playbackRate
                )
            )  // Use @Published property directly
            .font(.caption)
            .foregroundColor(.secondaryText)

            HStack(spacing: 8) {
                speedButton(for: 0.75)
                speedButton(for: 1.0)
                speedButton(for: 1.25)
                speedButton(for: 1.5)
                speedButton(for: 2.0)
            }
        }
    }

    // MARK: - Speed Button Helper
    @ViewBuilder
    private func speedButton(for speed: Double) -> some View {
        let isSelected = viewModel.playbackRate == Float(speed)  // Use @Published property directly

        Button(String(format: "%.2fx", speed)) {
            withHapticFeedback {
                DispatchQueue.main.async {
                    audioManager.setPlaybackRate(Float(speed))
                }
            }
        }
        .font(.caption)
        .fontWeight(isSelected ? .bold : .regular)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            if isSelected {
                Color.accentColor
            } else {
                Color.clear
            }
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
        .foregroundColor(isSelected ? .white : .primaryText)
    }

    // MARK: - Action Buttons
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 16) {
            PlayerActionButton(
                icon: "bookmark",
                title: NSLocalizedString(
                    "Bookmarks",
                    comment: "Bookmarks button title"
                ),
                count: bookmarks.count
            ) {
                showingBookmarks = true
            }

            PlayerActionButton(
                icon: "bookmark.circle",
                title: NSLocalizedString(
                    "Add Bookmark",
                    comment: "Add bookmark button title"
                )
            ) {
                showingAddBookmark = true
            }

            PlayerActionButton(
                icon: "doc.text",
                title: NSLocalizedString(
                    "Transcript",
                    comment: "Transcription button title"
                )
            ) {
                showingTranscription = true
            }

            if !chapters.isEmpty {
                PlayerActionButton(
                    icon: "list.bullet",
                    title: NSLocalizedString(
                        "Chapters",
                        comment: "Chapters button title"
                    ),
                    count: chapters.count
                ) {
                    showingChapterList = true
                }
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - Helper Methods
    private func loadAudiobook() {
        audioManager.loadAudiobook(audiobook)
    }

    // Sleep timer is handled by PlayerViewModel

    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    private func withHapticFeedback<T>(
        _ intensity: UIImpactFeedbackGenerator.FeedbackStyle = .light,
        _ action: () -> T
    ) -> T {
        let impact = UIImpactFeedbackGenerator(style: intensity)
        impact.prepare()
        let result = action()
        impact.impactOccurred()
        return result
    }

    private func formatAccessibilityTime(
        _ currentTime: TimeInterval,
        duration: TimeInterval
    ) -> String {
        let current = formatTime(currentTime)
        let total = formatTime(duration)
        let percentage = duration > 0 ? Int((currentTime / duration) * 100) : 0
        return String(
            format: NSLocalizedString(
                "%@ of %@, %d percent complete",
                comment: "Accessibility description for audio progress"
            ),
            current,
            total,
            percentage
        )
    }
}

#if false
    struct ActionButton: View {
        let icon: String
        let title: String
        var count: Int? = nil
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                VStack(spacing: 8) {
                    ZStack {
                        Image(systemName: icon)
                            .font(.title3)
                            .foregroundColor(.accentColor)

                        if let count = count, count > 0 {
                            Text("\(count)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.red)
                                .clipShape(Circle())
                                .offset(x: 12, y: -12)
                        }
                    }

                    Text(title)
                        .font(.caption)
                        .foregroundColor(.primaryText)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
#endif

