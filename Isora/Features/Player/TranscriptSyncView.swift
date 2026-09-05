import SwiftUI

/// A run of words the recogniser timed, grouped into something readable.
///
/// `SpeechTranscriber` hands back one segment per word, which is the right resolution for
/// seeking and the wrong one for reading: a thousand separate views per chapter, none of them
/// a sentence. Words are gathered into sentences here, keeping the first word's start and the
/// last word's end so a tap still lands where it should.
///
/// Times are shifted by `offset` at grouping time: the recogniser sees one chapter file and
/// counts from zero, while the player counts from the start of the book. Without the shift a
/// tap on chapter two seeks back into chapter one, and nothing ever highlights.
struct TranscriptSentence: Identifiable {
    let id = UUID()
    let text: String
    let start: TimeInterval
    let end: TimeInterval

    func contains(_ time: TimeInterval) -> Bool { time >= start && time < end }

    static func group(
        _ segments: [TranscriptionSegment],
        maxWords: Int = 24,
        offset: TimeInterval = 0
    ) -> [TranscriptSentence] {
        var sentences: [TranscriptSentence] = []
        var words: [TranscriptionSegment] = []

        func flush() {
            guard let first = words.first, let last = words.last else { return }
            let text = words.map(\.text).joined().trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                sentences.append(
                    TranscriptSentence(text: text, start: first.start + offset, end: last.end + offset)
                )
            }
            words.removeAll()
        }

        for segment in segments {
            words.append(segment)
            let ended = segment.text.trimmingCharacters(in: .whitespaces).last.map { ".!?…".contains($0) } ?? false
            if ended || words.count >= maxWords { flush() }
        }
        flush()
        return sentences
    }
}

/// The transcript lined up against playback: the sentence being spoken is highlighted, and
/// tapping any sentence seeks to it.
struct TranscriptSyncView: View {
    let sentences: [TranscriptSentence]
    let currentTime: TimeInterval
    let onSeek: (TimeInterval) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var activeID: UUID? {
        sentences.first { $0.contains(currentTime) }?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(sentences) { sentence in
                        let isActive = sentence.id == activeID
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(sentence.start.clockFormatted)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            Text(sentence.text)
                                .font(.body)
                                .lineSpacing(4)
                                .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { onSeek(sentence.start) }
                        .id(sentence.id)
                    }
                }
                .padding()
            }
            .onChange(of: activeID) { _, id in
                guard let id else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }
}
