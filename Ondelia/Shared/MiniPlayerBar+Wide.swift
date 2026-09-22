import SwiftUI

extension MiniPlayerBar {
    // MARK: - Wide accessory (design 6a / 7a)
    //
    // Regular width: the accessory is the transport for the Now Playing pane, so it carries the
    // chapter and its times, both skips, and the speed and sleep menus.
    @ViewBuilder
    var wideBar: some View {
        HStack(spacing: 16) {
            CoverArtView(audiobook: book, size: 40, cornerRadius: 9)

            VStack(alignment: .leading, spacing: 2) {
                Text(chapterOrTitle)
                    .font(.system(size: 14.5, weight: .semibold))
                    .lineLimit(1)
                Text(chapterTimes)
                    .font(.system(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 220, alignment: .leading)

            Spacer(minLength: 8)

            transportButton("gobackward.\(ThemeManager.shared.skipBackInterval.rawValue)", label: NSLocalizedString("Skip Backward", comment: "Skip backward accessibility label")) {
                audio.skipBackward()
            }

            Button {
                if audio.playbackState != .loading {
                    withHapticFeedback(.medium) { audio.togglePlayback() }
                }
            } label: {
                Group {
                    if audio.playbackState == .loading {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 46, height: 46)
                .background(.tint, in: Circle())
            }
            .accessibilityLabel(isPlaying ? NSLocalizedString("Pause", comment: "Pause playback") : NSLocalizedString("Play", comment: "Play playback"))
            .accessibilityIdentifier(AccessibilityIdentifiers.MiniPlayer.playPauseButton)

            transportButton("goforward.\(ThemeManager.shared.skipForwardInterval.rawValue)", label: NSLocalizedString("Skip Forward", comment: "Skip forward accessibility label")) {
                audio.skipForward()
            }

            Spacer(minLength: 8)

            Menu {
                ForEach(PlaybackSpeed.choices, id: \.self) { speed in
                    Button(PlaybackSpeed.displayName(speed)) { audio.setPlaybackRate(speed) }
                }
            } label: {
                Text(PlaybackSpeed.displayName(audio.getPlaybackRate()))
                    .monospacedDigit()
                    .glassPill(height: 36)
            }
            .accessibilityLabel(NSLocalizedString("Playback speed", comment: "Playback speed accessibility label"))

            Menu {
                SleepTimerMenuItems()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: audio.sleepTimeRemaining > 0 ? "moon.fill" : "moon")
                        .font(.system(size: 14, weight: .medium))
                    if audio.sleepTimeRemaining > 0 {
                        Text(audio.sleepTimeRemaining.clockFormatted).monospacedDigit()
                    }
                }
                .foregroundStyle(audio.sleepTimeRemaining > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .glassPill(height: 36, tinted: audio.sleepTimeRemaining > 0)
            }
            .accessibilityLabel(NSLocalizedString("Sleep Timer", comment: "Sleep timer accessibility label"))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
    }

    private func transportButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            withHapticFeedback { action() }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 40, height: 40)
                .glassEffect(.regular, in: Circle())
        }
        .accessibilityLabel(label)
    }

    private var currentChapter: ChapterModel? {
        guard let book else { return nil }
        let now = audio.getCurrentTime()
        return book.sortedChapters.first { now >= $0.startTime && now < $0.endTime }
    }

    private var chapterOrTitle: String {
        if let chapter = currentChapter {
            return chapter.title ?? String(
                format: NSLocalizedString("Chapter %d", comment: "Default chapter title with number"),
                chapter.chapterNumber
            )
        }
        return book?.title ?? NSLocalizedString("Unknown Title", comment: "Default title for audiobooks without title")
    }

    /// "17:22 · -33:38" inside the chapter, or the book's own position and time left.
    private var chapterTimes: String {
        let now = audio.getCurrentTime()
        let start = currentChapter?.startTime ?? 0
        let end = currentChapter?.endTime ?? audio.getDuration()
        let left = String(format: NSLocalizedString("-%@", comment: "Player: time remaining, negative clock format"), max(end - now, 0).clockFormatted)
        return "\((now - start).clockFormatted) · \(left)"
    }
}
