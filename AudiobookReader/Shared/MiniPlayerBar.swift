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
                        ?? NSLocalizedString("Unknown Title", comment: "")
                )
                .font(.subheadline).fontWeight(.semibold)
                .lineLimit(1)
                Text(
                    book?.author
                        ?? NSLocalizedString("Unknown Author", comment: "")
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
                Button {
                    audio.skipForward(15)
                } label: {
                    Image(systemName: "goforward.15")
                }
            }
            .font(.title3)
        }
        .padding(.horizontal, 16)
        .safeAreaPadding(.vertical, 6)
        .glassEffect(.clear)
    }
}

#Preview {
    MiniPlayerBar()
        .previewWithMockAudio(state:.playing)
}
