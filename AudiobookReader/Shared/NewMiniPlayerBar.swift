import SwiftUI

struct NewMiniPlayerBar: View {
    @ObservedObject var audio = GlobalAudioManager.shared
    @Environment(\.playerRouter) private var router

    private var book: AudiobookModel? { audio.currentAudiobook }
    private var isVisible: Bool { audio.showMiniPlayer && book != nil }
    private var isPlaying: Bool { audio.playbackState == .playing }

    private var cover: Image? {
        guard let data = book?.coverImageData, let ui = UIImage(data: data) else { return nil }
        return Image(uiImage: ui)
    }

    var body: some View {
        if isVisible, let book = book {
            HStack(spacing: 12) {
                // Cover
                (cover ?? Image(systemName: "book.closed"))
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                // Texts
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title ?? NSLocalizedString("Unknown Title", comment: ""))
                        .font(.subheadline).fontWeight(.semibold)
                        .lineLimit(1)
                    Text(book.author ?? NSLocalizedString("Unknown Author", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Controls
                HStack(spacing: 16) {
                    Button { audio.skipBackward(15) } label: {
                        Image(systemName: "gobackward.15")
                    }
                    Button {
                        if audio.playbackState != .loading { audio.togglePlayback() }
                    } label: {
                        Group {
                            if audio.playbackState == .loading {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            }
                        }
                    }
                    Button { audio.skipForward(15) } label: {
                        Image(systemName: "goforward.15")
                    }
                }
                .font(.title3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .onTapGesture {
                guard let router else { return }
                // Expand if already presenting this book
                if let presented = router.presented, presented.id == book.id {
                    router.selectedDetent = .large
                } else if !router.isDismissing {
                    router.presentFull(book)
                }
            }
        }
    }
}
