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
    /// Touchable height. The line itself is hairline-thin; a finger is not.
    private let touchHeight: CGFloat = 30

    /// Where the finger is, while it is down. The bar and the labels follow this instead of
    /// playback, so a drag is something you can see before you commit to it.
    @State private var dragFraction: Double?

    private var span: TimeInterval { max(range.upperBound - range.lowerBound, 1) }
    private var playedFraction: Double {
        min(max((position - range.lowerBound) / span, 0), 1)
    }
    /// What the bar shows: the finger while dragging, playback otherwise.
    private var shownFraction: Double { dragFraction ?? playedFraction }
    private var shownElapsed: TimeInterval { shownFraction * span }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text(
                    String(
                        format: NSLocalizedString(
                            "%@ into the chapter",
                            comment: "Player: elapsed time within the current chapter"
                        ),
                        shownElapsed.clockFormatted
                    )
                )

                Spacer(minLength: 0)

                Button(action: onToggleRemaining) {
                    Text(dragFraction == nil ? remainingLabel : dragRemainingLabel)
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                // Nothing to toggle mid-drag: the label is showing the finger, not playback.
                .disabled(dragFraction != nil)
            }
            .font(.system(size: 12))
            .monospacedDigit()
            .foregroundStyle(.secondary)

            GeometryReader { geometry in
                ProgressLine(value: shownFraction, height: height)
                    .frame(height: touchHeight, alignment: .center)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                dragFraction = ratio(at: value.location.x, in: geometry.size.width)
                            }
                            .onEnded { value in
                                let target = ratio(at: value.location.x, in: geometry.size.width)
                                dragFraction = nil
                                onSeek(range.lowerBound + target * span)
                            }
                    )
            }
            .frame(height: touchHeight)
            // The bar grew to fit a finger; the layout keeps the spacing it had.
            .padding(.vertical, -(touchHeight - height) / 2)
        }
        // VoiceOver — and the UI suite — reach this as the playback slider it stands in for.
        // The value has to be spelled out: a `Slider` inside a representation reports none of
        // its own, which is what left its position unreadable.
        .accessibilityRepresentation {
            Slider(
                value: Binding(
                    get: { shownFraction },
                    set: { onSeek(range.lowerBound + $0 * span) }
                ),
                in: 0...1
            )
                .accessibilityLabel(NSLocalizedString("Playback position", comment: "Player progress slider label"))
                .accessibilityValue(Text(Self.percentFormat.string(from: shownFraction as NSNumber) ?? ""))
                .accessibilityIdentifier(AccessibilityIdentifiers.Player.progressSlider)
        }
    }

    /// The value VoiceOver reads and the UI suite parses: a percentage, as a slider reports.
    private static let percentFormat: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        // Fixed locale: this string is parsed as a slider position, and a locale that writes
        // "4 %" with a non-breaking space is not a number to whatever reads it back.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private func ratio(at x: CGFloat, in width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(max(Double(x / width), 0), 1)
    }

    /// Time left in the chapter from where the finger is, so the right-hand label stays honest
    /// during a drag even when it was showing the book's remaining time.
    private var dragRemainingLabel: String {
        String(
            format: NSLocalizedString("%@ left", comment: "Player: time left in the chapter"),
            max(span - shownElapsed, 0).clockFormatted
        )
    }
}
