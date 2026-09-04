import SwiftUI

/// A run of words the recogniser timed, grouped into something readable.
///
/// `SpeechTranscriber` hands back one segment per word, which is the right resolution for
/// seeking and the wrong one for reading: a thousand separate views per chapter, none of them
/// a sentence. Words are gathered into sentences here, keeping the first word's start and the
/// last word's end so a tap still lands where it should.
struct TranscriptSentence: Identifiable {
    let id = UUID()
    let text: String
    let start: TimeInterval
    let end: TimeInterval

    func contains(_ time: TimeInterval) -> Bool { time >= start && time < end }

    static func group(_ segments: [TranscriptionSegment], maxWords: Int = 24) -> [TranscriptSentence] {
        var sentences: [TranscriptSentence] = []
        var words: [TranscriptionSegment] = []

        func flush() {
            guard let first = words.first, let last = words.last else { return }
            let text = words.map(\.text).joined().trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                sentences.append(TranscriptSentence(text: text, start: first.start, end: last.end))
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

    private var activeID: UUID? {
        sentences.first { $0.contains(currentTime) }?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(sentences) { sentence in
                        Text(sentence.text)
                            .font(.body)
                            .lineSpacing(4)
                            .foregroundStyle(sentence.id == activeID ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { onSeek(sentence.start) }
                            .id(sentence.id)
                    }
                }
                .padding()
            }
            .onChange(of: activeID) { _, id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }
}
