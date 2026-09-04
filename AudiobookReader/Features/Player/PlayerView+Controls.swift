import SwiftUI
import UIKit

extension PlayerView {
    // MARK: - Playback Controls
    @ViewBuilder
    var playbackControls: some View {
        HStack(spacing: 28) {
            Button {
                withHapticFeedback { audioManager.skipToPreviousChapter() }
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title3)
                    .foregroundStyle(Color.primaryText)
            }
            .disabled(chapters.isEmpty)
            .accessibilityLabel(NSLocalizedString("Previous Chapter", comment: "Previous chapter accessibility label"))
            .accessibilityIdentifier(AccessibilityIdentifiers.Player.previousChapterButton)

            Button {
                let skipInterval = themeManager.skipInterval.seconds
                withHapticFeedback {
                    audioManager.skipBackward(skipInterval)
                }
            } label: {
                Image(
                    systemName:
                        "gobackward.\(Int(themeManager.skipInterval.seconds))"
                )
                .font(.title)
                .foregroundStyle(Color.primaryText)
            }
            .accessibilityLabel(NSLocalizedString("Skip Backward", comment: "Skip backward accessibility label"))
            .accessibilityIdentifier(AccessibilityIdentifiers.Player.skipBackwardButton)

            Button {
                withHapticFeedback(.medium) {
                    if audioManager.playbackState != .loading {
                        audioManager.togglePlayback()
                    }
                }
            } label: {
                Group {
                    if audioManager.playbackState == .loading {
                        ProgressView()
                            .scaleEffect(1.8)
                            .progressViewStyle(.circular)
                            .tint(.accentColor)
                    } else {
                        Image(
                            systemName: isPlaying
                                ? "pause.circle.fill" : "play.circle.fill"
                        )
                        .font(.system(size: 80))
                        .foregroundStyle(.tint)
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
            .accessibilityLabel(
                isPlaying
                    ? NSLocalizedString("Pause", comment: "Pause playback accessibility label")
                    : NSLocalizedString("Play", comment: "Play playback accessibility label")
            )
            .accessibilityIdentifier(AccessibilityIdentifiers.Player.playPauseButton)

            Button {
                let skipInterval = themeManager.skipInterval.seconds
                withHapticFeedback {
                    audioManager.skipForward(skipInterval)
                }
            } label: {
                Image(
                    systemName:
                        "goforward.\(Int(themeManager.skipInterval.seconds))"
                )
                .font(.title)
                .foregroundStyle(Color.primaryText)
            }
            .accessibilityLabel(NSLocalizedString("Skip Forward", comment: "Skip forward accessibility label"))
            .accessibilityIdentifier(AccessibilityIdentifiers.Player.skipForwardButton)

            Button {
                withHapticFeedback { audioManager.skipToNextChapter() }
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title3)
                    .foregroundStyle(Color.primaryText)
            }
            .disabled(chapters.isEmpty)
            .accessibilityLabel(NSLocalizedString("Next Chapter", comment: "Next chapter accessibility label"))
            .accessibilityIdentifier(AccessibilityIdentifiers.Player.nextChapterButton)
        }
    }

    // MARK: - Speed Controls
    @ViewBuilder
    var speedControls: some View {
        VStack(spacing: 12) {
            Text(
                String(
                    format: NSLocalizedString(
                        "Speed: %@",
                        comment: "Playback speed display"
                    ),
                    PlaybackSpeed.displayName(playbackRate)
                )
            )
            .font(.caption)
            .foregroundStyle(Color.secondaryText)

            Menu {
                ForEach(PlaybackSpeed.choices, id: \.self) { speed in
                    speedButton(for: speed)
                }
            } label: {
                Label(PlaybackSpeed.displayName(playbackRate), systemImage: "speedometer")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.Player.speedControl)
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

    // MARK: - Action Buttons
    @ViewBuilder
    var actionButtons: some View {
        HStack(spacing: 16) {
            PlayerActionButton(
                icon: "bookmark",
                title: NSLocalizedString(
                    "Bookmarks",
                    comment: "Bookmarks button title"
                ),
                count: bookmarks.count,
                accessibilityIdentifier: AccessibilityIdentifiers.Player.bookmarksButton
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
        }
        .padding(.bottom, 16)
    }

    // MARK: - Helper Methods
    func loadAudiobook() {
        audioManager.loadAudiobook(audiobook)
    }

    // Sleep timer is handled by PlayerViewModel


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
