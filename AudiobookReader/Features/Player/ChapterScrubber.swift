import SwiftUI

/// The player's scrubber: how far into the chapter, how much of it is left, and a line that
/// seeks when it is dragged. Scoped to the chapter rather than the book — a twelve-hour bar
/// never visibly moves.
struct ChapterScrubber: View {
    /// Position in the book.
    let position: TimeInterval
    /// The chapter's span in the book, or the whole book when it has no chapters.
    let range: ClosedRange<TimeInterval>
    /// Right-hand label: what is left of the chapter, or of the book when toggled.
    let remainingLabel: String
    let onToggleRemaining: () -> Void
    let onSeek: (TimeInterval) -> Void

    var height: CGFloat = 6

    private var elapsed: TimeInterval { min(max(position - range.lowerBound, 0), span) }
    private var span: TimeInterval { max(range.upperBound - range.lowerBound, 1) }
    private var fraction: Double { elapsed / span }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text(
                    String(
                        format: NSLocalizedString(
                            "%@ into the chapter",
                            comment: "Player: elapsed time within the current chapter"
                        ),
                        elapsed.clockFormatted
                    )
                )

                Spacer(minLength: 0)

                Button(action: onToggleRemaining) {
                    Text(remainingLabel)
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 12))
            .monospacedDigit()
            .foregroundStyle(.secondary)

            GeometryReader { geometry in
                ProgressLine(value: fraction, height: height)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                let ratio = min(max(value.location.x / geometry.size.width, 0), 1)
                                onSeek(range.lowerBound + ratio * span)
                            }
                    )
            }
            .frame(height: height)
        }
        // VoiceOver — and the UI suite — reach this as the playback slider it stands in for.
        .accessibilityRepresentation {
            Slider(
                value: Binding(get: { position }, set: onSeek),
                in: range.lowerBound...max(range.upperBound, range.lowerBound + 1)
            )
            .accessibilityLabel(NSLocalizedString("Playback position", comment: "Player progress slider label"))
            .accessibilityIdentifier(AccessibilityIdentifiers.Player.progressSlider)
        }
        .accessibilityValue(remainingLabel)
    }
}
