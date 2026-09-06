import SwiftUI
import UIKit

extension PlayerView {
    // MARK: - Playback Controls
    //
    // The design's minimal transport: two glass seek circles around one white play target.
    // Chapter skips stay as bare glyphs at the edges — the mock drops them, but nothing else
    // on this screen moves a chapter at a time.
    @ViewBuilder
    var playbackControls: some View {
        HStack(spacing: 0) {
            Button {
                withHapticFeedback { audioManager.skipToPreviousChapter() }
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(chapters.isEmpty)
            .accessibilityLabel(NSLocalizedString("Previous Chapter", comment: "Previous chapter accessibility label"))
            .accessibilityIdentifier(AccessibilityIdentifiers.Player.previousChapterButton)

            Spacer(minLength: 8)

            Button {
                withHapticFeedback { audioManager.skipBackward(themeManager.skipInterval.seconds) }
            } label: {
                seekLabel("gobackward.\(Int(themeManager.skipInterval.seconds))")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("Skip Backward", comment: "Skip backward accessibility label"))
            .accessibilityIdentifier(AccessibilityIdentifiers.Player.skipBackwardButton)

            Spacer(minLength: 8)

            playPauseButton

            Spacer(minLength: 8)

            Button {
                withHapticFeedback { audioManager.skipForward(themeManager.skipInterval.seconds) }
            } label: {
                seekLabel("goforward.\(Int(themeManager.skipInterval.seconds))")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("Skip Forward", comment: "Skip forward accessibility label"))
            .accessibilityIdentifier(AccessibilityIdentifiers.Player.skipForwardButton)

            Spacer(minLength: 8)

            Button {
                withHapticFeedback { audioManager.skipToNextChapter() }
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(chapters.isEmpty)
            .accessibilityLabel(NSLocalizedString("Next Chapter", comment: "Next chapter accessibility label"))
            .accessibilityIdentifier(AccessibilityIdentifiers.Player.nextChapterButton)
        }
    }

    @ViewBuilder
    private func seekLabel(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .medium))
            .frame(width: 48, height: 48)
            .glassEffect(.regular, in: Circle())
    }

    @ViewBuilder
    var playPauseButton: some View {
        Button {
            withHapticFeedback(.medium) {
                if audioManager.playbackState != .loading {
                    audioManager.togglePlayback()
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 8)

                if audioManager.playbackState == .loading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.black)
                } else {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(.black)
                        .offset(x: isPlaying ? 0 : 2)
                }
            }
            .frame(width: 76, height: 76)
        }
        .buttonStyle(.plain)
        .disabled(audioManager.playbackState == .loading)
        .accessibilityLabel(
            isPlaying
                ? NSLocalizedString("Pause", comment: "Pause playback accessibility label")
                : NSLocalizedString("Play", comment: "Play playback accessibility label")
        )
        .accessibilityIdentifier(AccessibilityIdentifiers.Player.playPauseButton)
    }

    // MARK: - Chips
    //
    // Speed, sleep timer, bookmarks and the transcript, as the wide glass pills under the panel.
    @ViewBuilder
    var chipRow: some View {
        HStack(spacing: 9) {
            Menu {
                ForEach(PlaybackSpeed.choices, id: \.self) { speed in
                    speedButton(for: speed)
                }
            } label: {
                chip(PlaybackSpeed.displayName(playbackRate))
            }
            // Plain, like the two button chips: a menu label is tinted by default.
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("Playback speed", comment: "Playback speed accessibility label"))
            // The chip's own text is the rate; without this the label alone reaches VoiceOver.
            .accessibilityValue(PlaybackSpeed.displayName(playbackRate))
            .accessibilityIdentifier(AccessibilityIdentifiers.Player.speedControl)

            // A menu, like the speed chip, so it opens from the button.
            Menu {
                sleepTimerMenuItems
            } label: {
                // A running timer keeps its countdown beside the moon; otherwise the icon alone.
                iconChip(
                    sleepTimeRemaining > 0 ? "moon.fill" : "moon",
                    trailing: sleepTimeRemaining > 0 ? sleepTimeRemaining.clockFormatted : nil,
                    tinted: sleepTimeRemaining > 0
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("Sleep Timer", comment: "Sleep timer accessibility label"))
            .accessibilityValue(sleepTimeRemaining > 0 ? sleepTimeRemaining.clockFormatted : "")

            Button {
                showingBookmarks = true
            } label: {
                iconChip("bookmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("Bookmarks", comment: "Bookmarks button title"))
            .accessibilityIdentifier(AccessibilityIdentifiers.Player.bookmarksButton)

            Button {
                showingTranscription = true
            } label: {
                iconChip("text.alignleft")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("Transcript", comment: "Transcription button title"))
        }
    }

    @ViewBuilder
    private func chip(_ title: String) -> some View {
        Text(title)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .glassPill(height: 44)
    }

    /// The icon chips: sleep timer, bookmarks, transcript.
    @ViewBuilder
    private func iconChip(_ systemImage: String, trailing: String? = nil, tinted: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
            if let trailing {
                Text(trailing)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .foregroundStyle(tinted ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        .frame(maxWidth: .infinity)
        .glassPill(height: 44, tinted: tinted)
    }

    /// Shared by the moon chip and the running-timer row under "Up next".
    @ViewBuilder
    var sleepTimerMenuItems: some View {
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
            if sleepTimeRemaining > 0 {
                Button(
                    NSLocalizedString("Cancel timer", comment: "Sleep timer cancel action"),
                    role: .destructive
                ) { audioManager.cancelSleepTimer() }
            }
    }

    // MARK: - Speed Button Helper
    @ViewBuilder
    func speedButton(for speed: Float) -> some View {
        let isSelected = playbackRate == speed

        Button(PlaybackSpeed.displayName(speed)) {
            withHapticFeedback {
                audioManager.setPlaybackRate(speed)
            }
        }
        .fontWeight(isSelected ? .bold : .regular)
    }

    // MARK: - Helper Methods
    func loadAudiobook() {
        audioManager.loadAudiobook(audiobook)
    }

    func withHapticFeedback<T>(
        _ intensity: UIImpactFeedbackGenerator.FeedbackStyle = .light,
        _ action: () -> T
    ) -> T {
        let impact = UIImpactFeedbackGenerator(style: intensity)
        impact.prepare()
        let result = action()
        impact.impactOccurred()
        return result
    }

    func formatAccessibilityTime(
        _ currentTime: TimeInterval,
        duration: TimeInterval
    ) -> String {
        let current = currentTime.clockFormatted
        let total = duration.clockFormatted
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
