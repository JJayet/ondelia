import SwiftUI
import UIKit

extension PlayerView {
    // MARK: - Playback Controls
    @ViewBuilder
    var playbackControls: some View {
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
    var speedControls: some View {
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
    func speedButton(for speed: Double) -> some View {
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
    var actionButtons: some View {
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
        }
        .padding(.bottom, 16)
    }

    // MARK: - Helper Methods
    func loadAudiobook() {
        audioManager.loadAudiobook(audiobook)
    }

    // Sleep timer is handled by PlayerViewModel

    func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
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
