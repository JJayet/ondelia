import SwiftUI
import UIKit

struct MiniPlayerBar: View {
    let audio = GlobalAudioManager.shared

    /// The system moves the accessory into the minimized tab bar when the user scrolls down.
    /// That strip is one tab-bar row tall: cover, title and play/pause fit, nothing else does.
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    private var isInline: Bool { placement == .inline }

    private var book: AudiobookModel? { audio.currentAudiobook }
    private var isPlaying: Bool { audio.playbackState == .playing }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
            // Cover
            CoverArtView(audiobook: book, size: isInline ? 28 : 38, cornerRadius: isInline ? 9 : 12)

            // Texts
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    book?.title
                        ?? NSLocalizedString("Unknown Title", comment: "Default title for audiobooks without title")
                )
                .font(.subheadline).fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                if !isInline {
                    Text(
                        book?.author
                            ?? NSLocalizedString("Unknown Author", comment: "Default author for audiobooks without author")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
            }

            Spacer()

            // Controls
            HStack(spacing: 16) {
                if !isInline {
                    Button {
                        audio.skipBackward()
                    } label: {
                        Image(systemName: "gobackward.\(ThemeManager.shared.skipInterval.rawValue)")
                    }
                    .accessibilityLabel(NSLocalizedString("Skip Backward", comment: "Skip backward accessibility label"))
                }
                Button {
                    if audio.playbackState != .loading {
                        audio.togglePlayback()
                    }
                } label: {
                    Group {
                        if audio.playbackState == .loading {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(
                                systemName: isPlaying
                                    ? "pause.fill" : "play.fill"
                            )
                        }
                    }
                }
                .accessibilityLabel(isPlaying ? NSLocalizedString("Pause", comment: "Pause playback") : NSLocalizedString("Play", comment: "Play playback"))
                .accessibilityIdentifier(AccessibilityIdentifiers.MiniPlayer.playPauseButton)
                if !isInline {
                    Button {
                        audio.skipForward()
                    } label: {
                        Image(systemName: "goforward.\(ThemeManager.shared.skipInterval.rawValue)")
                    }
                    .accessibilityLabel(NSLocalizedString("Skip Forward", comment: "Skip forward accessibility label"))
                    Button {
                        audio.stopPlayback()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(NSLocalizedString("Close Player", comment: "Close mini player"))
                    .accessibilityIdentifier(AccessibilityIdentifiers.MiniPlayer.closeButton)
                }
            }
            .font(.title3)
            }

            if !isInline {
                MiniPlayerProgress()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        // The accessory is one tap target: without a shape, the gaps between cover, text and
        // buttons swallow the tap that expands the player.
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityIdentifiers.MiniPlayer.container)
    }
}

/// Its own view so the position, which lands about four times a second, redraws the bar itself
/// and not the cover, the titles and the buttons with it.
private struct MiniPlayerProgress: View {
    let audio = GlobalAudioManager.shared

    var body: some View {
        ProgressView(
            value: min(max(audio.getCurrentTime(), 0), max(audio.getDuration(), 1)),
            total: max(audio.getDuration(), 1)
        )
        .accessibilityIdentifier(AccessibilityIdentifiers.MiniPlayer.progressBar)
    }
}

#Preview {
    MiniPlayerBar()
}
