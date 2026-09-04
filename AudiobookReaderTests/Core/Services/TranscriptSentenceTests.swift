import Foundation
import Testing
@testable import AudiobookReader

struct TranscriptSentenceTests {
    private func words(_ pairs: [(String, Double, Double)]) -> [TranscriptionSegment] {
        pairs.map { TranscriptionSegment(text: $0.0, start: $0.1, end: $0.2) }
    }

    @Test("Words are grouped up to the end of each sentence")
    func groupsOnSentenceEnd() {
        let sentences = TranscriptSentence.group(words([
            ("Hello ", 0, 1), ("there.", 1, 2),
            ("How ", 2, 3), ("are ", 3, 4), ("you?", 4, 5)
        ]))

        #expect(sentences.map(\.text) == ["Hello there.", "How are you?"])
        #expect(sentences[0].start == 0)
        #expect(sentences[0].end == 2)
        #expect(sentences[1].start == 2)
        #expect(sentences[1].end == 5)
    }

    @Test("A sentence that never ends is cut at the word limit")
    func groupsOnWordLimit() {
        let segments = words((0..<10).map { ("word\($0) ", Double($0), Double($0) + 1) })
        let sentences = TranscriptSentence.group(segments, maxWords: 4)

        #expect(sentences.count == 3)
        #expect(sentences[0].end == 4)
        #expect(sentences[2].text == "word8 word9")
    }

    @Test("The sentence being spoken is the one holding the playhead")
    func containsThePlayhead() {
        let sentence = TranscriptSentence.group(words([("Only ", 10, 11), ("this.", 11, 12)]))[0]

        #expect(sentence.contains(10))
        #expect(sentence.contains(11.5))
        #expect(!sentence.contains(12))
        #expect(!sentence.contains(9.9))
    }

    @Test("Segments without timings produce no sentences")
    func emptyInput() {
        #expect(TranscriptSentence.group([]).isEmpty)
    }
}
