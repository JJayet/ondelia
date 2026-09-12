import AVFoundation
import CoreMedia
import Speech

/// One stretch of an audio file as analyzer input, converted to the analyzer's format one
/// chunk per pull. Pull-based, so nothing is decoded ahead of what the recogniser consumes
/// and a cancelled analysis stops reading the file at once.
struct AudioWindowSequence: AsyncSequence, Sendable {
    typealias Element = AnalyzerInput

    let url: URL
    /// Seconds from the start of the file.
    let start: TimeInterval
    let end: TimeInterval
    let format: AVAudioFormat

    func makeAsyncIterator() -> Iterator {
        Iterator(url: url, start: start, end: end, format: format)
    }

    struct Iterator: AsyncIteratorProtocol {
        private static let chunk: AVAudioFrameCount = 32_768

        let url: URL
        let start: TimeInterval
        let end: TimeInterval
        let format: AVAudioFormat

        private var file: AVAudioFile?
        private var converter: AVAudioConverter?
        private var endFrame: AVAudioFramePosition = 0
        private var stampedFirst = false

        init(url: URL, start: TimeInterval, end: TimeInterval, format: AVAudioFormat) {
            self.url = url
            self.start = start
            self.end = end
            self.format = format
        }

        mutating func next() async throws -> AnalyzerInput? {
            if file == nil { try open() }
            guard let file, file.framePosition < endFrame else { return nil }

            // Only the first buffer is stamped, so results carry file time and not window time.
            // The rest chain off the previous buffer's end: the resampler's output lengths do
            // not line up exactly with file positions, and stamping each one made the analyzer
            // see overlaps ("Audio input timestamp overlaps or precedes prior audio input").
            let startTime: CMTime? = stampedFirst
                ? nil
                : CMTime(value: file.framePosition, timescale: CMTimeScale(file.processingFormat.sampleRate))
            stampedFirst = true
            let frames = AVAudioFrameCount(Swift.min(AVAudioFramePosition(Self.chunk), endFrame - file.framePosition))
            guard let raw = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else {
                throw TranscriptionError.audioUnreadable
            }
            try file.read(into: raw, frameCount: frames)
            guard raw.frameLength > 0 else { return nil }
            return AnalyzerInput(buffer: try convert(raw), bufferStartTime: startTime)
        }

        private mutating func open() throws {
            let file = try AVAudioFile(forReading: url)
            let rate = file.processingFormat.sampleRate
            file.framePosition = AVAudioFramePosition(start * rate)
            endFrame = Swift.min(AVAudioFramePosition(end * rate), file.length)
            if file.processingFormat != format {
                converter = AVAudioConverter(from: file.processingFormat, to: format)
            }
            self.file = file
        }

        private func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
            guard let converter else { return buffer }
            let ratio = format.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
            guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
                throw TranscriptionError.audioUnreadable
            }

            // Hand the converter this one buffer and then report "no more for now", never end of
            // stream: the converter keeps its resampling state across chunks that way.
            // The input block is `@Sendable`; the buffer is handed over once and never touched
            // again here, so the capture is safe even though AVAudioPCMBuffer is not Sendable.
            nonisolated(unsafe) var pending: AVAudioPCMBuffer? = buffer
            var conversionError: NSError?
            converter.convert(to: converted, error: &conversionError) { _, status in
                guard let input = pending else {
                    status.pointee = .noDataNow
                    return nil
                }
                pending = nil
                status.pointee = .haveData
                return input
            }
            if let conversionError { throw conversionError }
            return converted
        }
    }
}
