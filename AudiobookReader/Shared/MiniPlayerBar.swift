import SwiftUI
import UIKit

struct MiniPlayerBar: View {
    @ObservedObject var audio = GlobalAudioManager.shared

    private var book: AudiobookModel? { audio.currentAudiobook }
    private var isPlaying: Bool { audio.playbackState == .playing }

    private var cover: Image? {
        guard let data = book?.coverImageData, let ui = UIImage(data: data)
        else { return nil }
        return Image(uiImage: ui)
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
            // Cover
            (cover ?? Image(systemName: "book.closed"))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 30)

            // Texts
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    book?.title
                        ?? NSLocalizedString("Unknown Title", comment: "Default title for audiobooks without title")
                )
                .font(.subheadline).fontWeight(.semibold)
                .lineLimit(1)
                Text(
                    book?.author
                        ?? NSLocalizedString("Unknown Author", comment: "Default author for audiobooks without author")
                )
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }

            Spacer()

            // Controls
            HStack(spacing: 16) {
                Button {
                    audio.skipBackward(15)
                } label: {
                    Image(systemName: "gobackward.15")
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
                Button {
                    audio.skipForward(15)
                } label: {
                    Image(systemName: "goforward.15")
                }
                Button {
                    audio.stopPlayback()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel(NSLocalizedString("Close Player", comment: "Close mini player"))
                .accessibilityIdentifier(AccessibilityIdentifiers.MiniPlayer.closeButton)
            }
            .font(.title3)
            }

            ProgressView(
                value: min(max(audio.getCurrentTime(), 0), max(audio.getDuration(), 1)),
                total: max(audio.getDuration(), 1)
            )
            .accessibilityIdentifier(AccessibilityIdentifiers.MiniPlayer.progressBar)
        }
        .padding(.horizontal, 16)
        .safeAreaPadding(.vertical, 6)
        .glassEffect(.clear)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityIdentifiers.MiniPlayer.container)
    }
}

#Preview {
    MiniPlayerBar()
        .previewWithMockAudio(state:.playing)
}
