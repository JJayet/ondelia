import SwiftUI
import UIKit

struct MiniPlayerBar: View {
    let audio = GlobalAudioManager.shared
    /// The zoom into the full player flies from here.
    let namespace: Namespace.ID

    /// The system moves the accessory into the minimized tab bar when the user scrolls down.
    /// That strip is one tab-bar row tall: cover, title and play/pause fit, nothing else does.
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    private var isInline: Bool { placement == .inline }

    private var book: AudiobookModel? { audio.currentAudiobook }
    private var isPlaying: Bool { audio.playbackState == .playing }

    var body: some View {
        // The accessory exists twice — expanded above the tab bar and inline inside it — and
        // a source on both sends the zoom to whichever the system resolves first, which was
        // the hidden inline copy: the player shrank into the bottom-left corner.
        if isInline {
            bar
        } else {
            bar.matchedTransitionSource(id: "MINIPLAYER", in: namespace)
        }
    }

    private var bar: some View {
        HStack(spacing: 12) {
            CoverArtView(audiobook: book, size: isInline ? 28 : 40, cornerRadius: isInline ? 7 : 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(
                    book?.title
                        ?? NSLocalizedString("Unknown Title", comment: "Default title for audiobooks without title")
                )
                .font(.subheadline).fontWeight(.medium)
                .lineLimit(1)
                if !isInline {
                    Text(
                        book?.author
                            ?? NSLocalizedString("Unknown Author", comment: "Default author for audiobooks without author")
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Button {
                if audio.playbackState != .loading {
                    audio.togglePlayback()
                }
            } label: {
                Group {
                    if audio.playbackState == .loading {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(isPlaying ? NSLocalizedString("Pause", comment: "Pause playback") : NSLocalizedString("Play", comment: "Play playback"))
            .accessibilityIdentifier(AccessibilityIdentifiers.MiniPlayer.playPauseButton)

            if !isInline {
                Button {
                    audio.skipForward()
                } label: {
                    Image(systemName: "goforward.\(ThemeManager.shared.skipInterval.rawValue)")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(NSLocalizedString("Skip Forward", comment: "Skip forward accessibility label"))
            }
        }
        .font(.title3)
        .buttonStyle(.plain)
        .padding(.leading, 12)
        .padding(.trailing, 4)
        // The accessory is one tap target: without a shape, the gaps between cover, text and
        // buttons swallow the tap that expands the player.
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityIdentifiers.MiniPlayer.container)
    }
}

#Preview {
    @Previewable @Namespace var namespace
    MiniPlayerBar(namespace: namespace)
}
