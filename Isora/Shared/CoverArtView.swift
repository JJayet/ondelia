import SwiftUI

/// Square cover art, used at every size from the mini player to the full player.
///
/// A book with no artwork gets the design's typographic placeholder — a gradient taken from the
/// same tint the screen is painted with, the title at the top, the author along the bottom —
/// instead of the grey `book.closed` glyph the app used to show.
struct CoverArtView: View {
    let audiobook: AudiobookModel?
    /// Fixed side, or `nil` to fill the available width as a square (library grid).
    var size: CGFloat?
    var cornerRadius: CGFloat = 16

    var body: some View {
        if let size {
            art(side: size).frame(width: size, height: size)
        } else {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { GeometryReader { geometry in art(side: geometry.size.width) } }
        }
    }

    private func art(side: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return Group {
            if let image = CoverImageCache.image(for: audiobook) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                placeholder(side: side)
            }
        }
        .frame(width: side, height: side)
        .clipShape(shape)
        .overlay {
            // The lit top-left edge every card in the design carries.
            shape
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.18), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.5), radius: side * 0.12, y: side * 0.06)
        .accessibilityLabel(
            String(
                format: NSLocalizedString("Cover of %@", comment: "Audiobook cover accessibility label"),
                audiobook?.title ?? AudiobookModel.unknownTitle
            )
        )
    }

    /// Placeholder text is dropped below 44pt: at that size it is unreadable and reads as noise.
    @ViewBuilder
    private func placeholder(side: CGFloat) -> some View {
        let tint = CoverTintCache.tint(for: audiobook)
        LinearGradient(colors: [tint.primary, tint.secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(alignment: .topLeading) {
                if side >= 44 {
                    VStack(alignment: .leading) {
                        Text(audiobook?.title ?? AudiobookModel.unknownTitle)
                            .font(.system(size: side * 0.115, weight: .bold))
                            .lineLimit(3)
                        Spacer(minLength: 0)
                        Text((audiobook?.author ?? AudiobookModel.unknownAuthor).uppercased())
                            .font(.system(size: side * 0.055, weight: .semibold))
                            .tracking(side * 0.007)
                            .lineLimit(1)
                            .opacity(0.75)
                    }
                    .foregroundStyle(.white)
                    .padding(side * 0.075)
                }
            }
    }
}
