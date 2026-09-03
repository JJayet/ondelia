import Testing
@testable import AudiobookReader

@MainActor
struct WhisperTranscriptionMappingTests {
    @Test("Whisper segment timing and text are preserved")
    func segmentTimingIsPreserved() {
        let result = WhisperTranscriptionManager.makeSegments([
            (text: " First", start: 0.25, end: 1.5),
            (text: " second", start: 1.5, end: 3.75)
        ])

        #expect(result == [
            TranscriptionSegment(text: " First", start: 0.25, end: 1.5),
            TranscriptionSegment(text: " second", start: 1.5, end: 3.75)
        ])
    }

    @Test("Invalid Whisper segment ranges are discarded")
    func invalidSegmentRangesAreDiscarded() {
        let result = WhisperTranscriptionManager.makeSegments([
            (text: "negative", start: -1, end: 1),
            (text: "backwards", start: 3, end: 2),
            (text: "valid", start: 2, end: 3)
        ])

        #expect(result == [TranscriptionSegment(text: "valid", start: 2, end: 3)])
    }
}
