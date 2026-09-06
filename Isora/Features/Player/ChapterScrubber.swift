import SwiftUI

/// The player's scrubber: two lines of time — the book's, the chapter's — over a line that
/// seeks when it is dragged. The bar spans the chapter or the whole book; tapping the times
/// switches, and the line the bar is following reads brighter than the other.
struct ChapterScrubber: View {
    /// Position in the book.
    let position: TimeInterval
    let duration: TimeInterval
    let chapters: [ChapterModel]
    let onSeek: (TimeInterval) -> Void

    static let showChapterTimesKey = "player.showChapterTimes"
    /// Settings > Playback: whether the chapter line shows at all.
    @AppStorage(ChapterScrubber.showChapterTimesKey) private var showsChapterTimes = true
    /// Whether the bar spans the book. Off — the chapter — by default: a twelve-hour bar never
    /// visibly moves.
    @AppStorage("player.scrubsBook") private var scrubsBook = false

    var height: CGFloat = 6
    /// Touchable height. The line itself is hairline-thin; a finger is not.
    private let touchHeight: CGFloat = 30

    /// Where the finger is, while it is down. The bar and the labels follow this instead of
    /// playback, so a drag is something you can see before you commit to it.
    @State private var dragFraction: Double?

    /// The span of the chapter around `time`, or nil when the book has none there.
    private func chapterRange(at time: TimeInterval) -> ClosedRange<TimeInterval>? {
        guard let chapter = chapters.last(where: { $0.startTime <= time }) ?? chapters.first,
              chapter.endTime > chapter.startTime
        else { return nil }
        return chapter.startTime...chapter.endTime
    }

    /// What the bar spans. Pinned to playback, not the finger, so it holds still during a drag.
    private var range: ClosedRange<TimeInterval> {
        (scrubsBook ? nil : chapterRange(at: position)) ?? 0...max(duration, 1)
    }
    private var span: TimeInterval { max(range.upperBound - range.lowerBound, 1) }
    private var playedFraction: Double {
        min(max((position - range.lowerBound) / span, 0), 1)
    }
    /// What the bar shows: the finger while dragging, playback otherwise.
    private var shownFraction: Double { dragFraction ?? playedFraction }
    /// Position in the book the bar shows.
    private var shownPosition: TimeInterval { range.lowerBound + shownFraction * span }
    private var showsChapterLine: Bool { showsChapterTimes && !chapters.isEmpty }

    var body: some View {
        VStack(spacing: 10) {
            Button {
                scrubsBook.toggle()
            } label: {
                VStack(spacing: 4) {
                    timeLine(
                        shownPosition.clockFormatted,
                        String(
                            format: NSLocalizedString("%@ left in the book", comment: "Player: time left in the book"),
                            max(duration - shownPosition, 0).clockFormatted
                        ),
                        active: scrubsBook || !showsChapterLine
                    )
                    // Follows the finger across chapters when the bar spans the book.
                    if showsChapterLine, let chapter = chapterRange(at: shownPosition) {
                        timeLine(
                            String(
                                format: NSLocalizedString(
                                    "%@ into the chapter",
                                    comment: "Player: elapsed time within the current chapter"
                                ),
                                max(shownPosition - chapter.lowerBound, 0).clockFormatted
                            ),
                            String(
                                format: NSLocalizedString("%@ left", comment: "Player: time left in the chapter"),
                                max(chapter.upperBound - shownPosition, 0).clockFormatted
                            ),
                            active: !scrubsBook
                        )
                    }
                }
                .font(.system(size: 12))
                .monospacedDigit()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(chapters.isEmpty)
            .accessibilityLabel(NSLocalizedString("Progress bar spans", comment: "Player: what the scrubber covers"))
            .accessibilityValue(
                scrubsBook
                    ? NSLocalizedString("The book", comment: "Player: scrubber spans the book")
                    : NSLocalizedString("The chapter", comment: "Player: scrubber spans the chapter")
            )

            GeometryReader { geometry in
                ProgressLine(value: shownFraction, height: height)
                    .frame(height: touchHeight, alignment: .center)
                    .contentShape(Rectangle())
                    // A tap is not a seek: the bar is too easy to brush on the way to the
                    // buttons under it. The finger has to travel first.
                    .gesture(
                        DragGesture(minimumDistance: 8)
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

    @ViewBuilder
    private func timeLine(_ leading: String, _ trailing: String, active: Bool) -> some View {
        HStack(spacing: 8) {
            Text(leading)
            Spacer(minLength: 0)
            Text(trailing)
        }
        .foregroundStyle(active ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
    }
}
