import SwiftUI

/// The player's scrubber, drawn as the design's bar waveform: the part already heard in the
/// accent colour, the rest dimmed, and a drag anywhere on it seeks.
///
/// The bars are not real audio. Decoding a whole book to draw one would cost far more than the
/// picture is worth, so the heights come from the book's own id — stable for a given book,
/// different between books, and never the flat ramp a fixed pattern would give.
struct WaveformScrubber: View {
    let position: TimeInterval
    let duration: TimeInterval
    /// A stable seed, so the same book always draws the same waveform.
    let seed: UUID
    let onSeek: (TimeInterval) -> Void

    var barCount: Int = 34
    var height: CGFloat = 34

    private var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 3
            let barWidth = max((geometry.size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount), 1)
            let playedBars = Int((Double(barCount) * fraction).rounded())

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(index < playedBars ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                        .frame(width: barWidth, height: height * Self.barHeight(index: index, seed: seed))
                }
            }
            .frame(height: height, alignment: .bottom)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let ratio = min(max(value.location.x / geometry.size.width, 0), 1)
                        onSeek(ratio * duration)
                    }
            )
        }
        .frame(height: height)
        // VoiceOver — and the UI suite — reach this as the playback slider it stands in for.
        .accessibilityRepresentation {
            Slider(
                value: Binding(get: { position }, set: onSeek),
                in: 0...max(duration, 1)
            )
            .accessibilityLabel(NSLocalizedString("Playback position", comment: "Player progress slider label"))
            .accessibilityIdentifier(AccessibilityIdentifiers.Player.progressSlider)
        }
    }

    /// 0.25...1 of the full height, hashed from the bar's index and the book's id.
    ///
    /// Hand-rolled FNV rather than `Hasher`, which is seeded per process: the waveform would
    /// then be a different picture on every launch.
    static func barHeight(index: Int, seed: UUID) -> CGFloat {
        var value = UInt64(index &+ 1) &* 0x9E37_79B9_7F4A_7C15
        withUnsafeBytes(of: seed.uuid) { bytes in
            for byte in bytes { value = (value ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
        }
        value ^= value >> 33
        return 0.25 + 0.75 * CGFloat(value % 1000) / 1000
    }
}
