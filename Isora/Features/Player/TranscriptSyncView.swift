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
struct TranscriptSentence: Identifiable, Equatable {
    /// Sentences never share a start, and a stable id is what keeps the rows in place: a fresh
    /// UUID per grouping made every playback tick rebuild the list and re-target the scroll.
    var id: TimeInterval { start }
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

extension Array where Element == TranscriptSentence {
    /// The sentence being spoken at `time`, or the last one that started before it. Binary
    /// search: sentences are in start order, and this runs four times a second on a list that
    /// can hold every sentence of a single-file book.
    func sentenceID(at time: TimeInterval) -> TranscriptSentence.ID? {
        var low = 0
        var high = count
        while low < high {
            let mid = (low + high) / 2
            if self[mid].start <= time { low = mid + 1 } else { high = mid }
        }
        return low > 0 ? self[low - 1].id : nil
    }
}

/// The transcript lined up against playback: the sentence being spoken is highlighted, and
/// tapping any sentence seeks to it.
///
/// This layer is the only one that watches the clock. It turns the 4 Hz position into a
/// sentence id, and the rows below only rebuild when that id changes.
struct TranscriptSyncView: View {
    let sentences: [TranscriptSentence]
    let onSeek: (TimeInterval) -> Void
    private let audio = GlobalAudioManager.shared

    var body: some View {
        TranscriptRows(sentences: sentences, activeID: sentences.sentenceID(at: audio.getCurrentTime()), onSeek: onSeek)
            .equatable()
    }
}

/// A `List`, not a `LazyVStack`: the collection view underneath keeps only the visible rows
/// alive and can jump to any row without laying out the thousands before it.
private struct TranscriptRows: View, Equatable {
    let sentences: [TranscriptSentence]
    let activeID: TranscriptSentence.ID?
    let onSeek: (TimeInterval) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.activeID == rhs.activeID && lhs.sentences == rhs.sentences
    }

    var body: some View {
        ScrollViewReader { proxy in
            List(sentences) { sentence in
                row(sentence, isActive: sentence.id == activeID)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .id(sentence.id)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // Opening the transcript lands on the line being spoken, not on the first page.
            .onAppear {
                guard let activeID else { return }
                proxy.scrollTo(activeID, anchor: .center)
            }
            .onChange(of: activeID) { _, id in
                guard let id else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func row(_ sentence: TranscriptSentence, isActive: Bool) -> some View {
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
        .onTapGesture { withHapticFeedback { onSeek(sentence.start) } }
    }
}
