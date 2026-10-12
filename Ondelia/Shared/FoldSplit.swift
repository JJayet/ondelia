import SwiftUI

/// iPhone Duo's inner display: the vertical band the fold runs through (design 9). Apple asks
/// that nothing sit there while the device is half open; the band is kept when it opens flat
/// too, so nothing moves as the angle changes.
enum FoldDivision {
    /// The design's band: wider than the crease itself, so no control lands on the slope.
    static let minimumWidth: CGFloat = 56
    /// Below this either side is too narrow to be a screen of its own; keep the usual layout.
    static let minimumPaneWidth: CGFloat = 280

    /// The band's horizontal span in `geometry`'s own coordinates, or nil when no vertical fold
    /// crosses it with room on both sides: iOS 26, a phone, the outer display, a tabletop fold.
    static func band(in geometry: GeometryProxy) -> Range<CGFloat>? {
        guard #available(iOS 27.1, *) else { return nil }
        let width = geometry.size.width
        for region in geometry.reservedRegions(kind: .division, options: .includeInactive) {
            let frame = region.frame
            guard frame.height > frame.width else { continue }
            // The crease alone: each half pads its own content, so the region's margins on top
            // of that left a gap far wider than the design's band.
            let half = max(frame.width, minimumWidth) / 2
            let band = (frame.midX - half)..<(frame.midX + half)
            if band.lowerBound >= minimumPaneWidth, width - band.upperBound >= minimumPaneWidth {
                return band
            }
        }
        return nil
    }
}

extension EnvironmentValues {
    /// True while the window is laid out around the fold (see `FoldDivision`). Set once by the
    /// tab view; screens read it for what sits outside their `FoldSplit`, like a toolbar title.
    @Entry var isFoldSplit = false
}

/// Two screens either side of the fold, nothing in it; `fallback` everywhere else.
///
/// The mini player leaves the tab bar's accessory, which the system centres on the fold, for
/// its own row at the bottom of the left half.
struct FoldSplit<Primary: View, Secondary: View, Fallback: View>: View {
    /// Off on the player itself: its transport would be shown twice.
    var showsMiniPlayer = true
    @ViewBuilder var primary: Primary
    @ViewBuilder var secondary: Secondary
    @ViewBuilder var fallback: Fallback

    var body: some View {
        GeometryReader { geometry in
            if let band = FoldDivision.band(in: geometry) {
                HStack(spacing: 0) {
                    primary
                        .frame(width: band.lowerBound)
                        .safeAreaInset(edge: .bottom) {
                            if showsMiniPlayer { FoldMiniPlayer() }
                        }
                    // The fold: nothing drawn, nothing to tap.
                    Color.clear
                        .frame(width: band.upperBound - band.lowerBound)
                        .accessibilityHidden(true)
                    secondary
                        .frame(maxWidth: .infinity)
                }
            } else {
                fallback
            }
        }
    }
}

/// The mini player as a row of the left half: same bar, docked, on its own glass.
private struct FoldMiniPlayer: View {
    private let audio = GlobalAudioManager.shared
    @Environment(\.playerRouter) private var playerRouter
    @Namespace private var namespace

    var body: some View {
        if let book = audio.currentAudiobook, audio.showMiniPlayer {
            MiniPlayerBar(namespace: namespace, docked: true)
                .frame(height: 68)
                .glassEffect(.regular, in: Capsule())
                // The gaps between cover, text and buttons would swallow the tap otherwise.
                .contentShape(Capsule())
                .onTapGesture { withHapticFeedback { playerRouter?.present(book) } }
                .accessibilityAction(
                    named: Text(NSLocalizedString("Open Player", comment: "Accessibility action: expand the mini player"))
                ) {
                    playerRouter?.present(book)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
    }
}
