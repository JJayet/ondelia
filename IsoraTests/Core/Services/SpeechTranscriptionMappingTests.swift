import Foundation
import CoreMedia
import Speech
import Testing
@testable import Isora

@MainActor
struct SpeechTranscriptionMappingTests {
    @Test("Segment timing and text are preserved")
    func segmentTimingIsPreserved() {
        let result = SpeechTranscriptionManager.makeSegments([
            (text: " First", start: 0.25, end: 1.5),
            (text: " second", start: 1.5, end: 3.75)
        ])

        #expect(result == [
            TranscriptionSegment(text: " First", start: 0.25, end: 1.5),
            TranscriptionSegment(text: " second", start: 1.5, end: 3.75)
        ])
    }

    @Test("Segments the recogniser could not place are discarded")
    func invalidSegmentRangesAreDiscarded() {
        let result = SpeechTranscriptionManager.makeSegments([
            (text: "negative", start: -1, end: 1),
            (text: "backwards", start: 3, end: 2),
            (text: "not-a-number", start: .nan, end: 1),
            (text: "infinite", start: 0, end: .infinity),
            (text: "valid", start: 2, end: 3)
        ])

        #expect(result == [TranscriptionSegment(text: "valid", start: 2, end: 3)])
    }

    @Test("Timings come from the audio time range of each run")
    func timingsAreReadFromAudioTimeRanges() {
        var attributed = AttributedString("hello")
        attributed.audioTimeRange = CMTimeRange(
            start: CMTime(seconds: 1, preferredTimescale: 600),
            end: CMTime(seconds: 2, preferredTimescale: 600)
        )
        var untimed = AttributedString(" world")
        untimed.audioTimeRange = nil
        attributed.append(untimed)

        let timings = SpeechTranscriptionManager.timings(in: attributed)

        #expect(timings.count == 1)
        #expect(timings.first?.text == "hello")
        #expect(timings.first?.start == 1)
        #expect(timings.first?.end == 2)
    }
}
