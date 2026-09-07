import Foundation
import Testing
@testable import Isora

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

    @Test("An offset moves the sentence onto the player's timeline")
    func appliesChapterOffset() {
        let sentences = TranscriptSentence.group(
            words([("Second ", 0, 1), ("chapter.", 1, 2)]),
            offset: 600
        )

        #expect(sentences[0].start == 600)
        #expect(sentences[0].end == 602)
        #expect(sentences[0].contains(601))
        #expect(!sentences[0].contains(1))
    }

    @Test("Segments without timings produce no sentences")
    func emptyInput() {
        #expect(TranscriptSentence.group([]).isEmpty)
    }

    @Test("sentenceID(at:) finds the sentence spoken, or the last one started")
    func sentenceLookup() {
        let sentences = (0..<5).map {
            TranscriptSentence(text: "s\($0)", start: Double($0 * 10), end: Double($0 * 10 + 8))
        }
        #expect(sentences.sentenceID(at: -1) == nil)
        #expect(sentences.sentenceID(at: 0) == 0)
        #expect(sentences.sentenceID(at: 25) == 20)
        #expect(sentences.sentenceID(at: 29) == 20) // in the gap, keeps the last one
        #expect(sentences.sentenceID(at: 1000) == 40)
        #expect([TranscriptSentence]().sentenceID(at: 5) == nil)
    }
}
