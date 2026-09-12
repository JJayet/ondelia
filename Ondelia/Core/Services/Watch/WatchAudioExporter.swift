import AVFoundation
import Foundation

/// One chapter of audio, cut down to something a watch can hold and receive over Bluetooth:
/// AAC 64 kbps mono. Roughly 25 MB per listening hour.
///
/// The input is deliberately a plain value rather than the SwiftData row, so the cut can be
/// tested against a generated asset without a model container.
/// `WatchAudioExporter+Model.swift` builds one from an `AudiobookModel`.
enum WatchAudioExporter {

    /// What to read. A folder book's chapter is a whole file (`timeRange` nil); a single-file
    /// book's chapter is a range of the one file.
    struct ExportSource: Sendable, Equatable {
        let fileURL: URL
        let timeRange: CMTimeRange?

        init(fileURL: URL, timeRange: CMTimeRange? = nil) {
            self.fileURL = fileURL
            self.timeRange = timeRange
        }
    }

    enum ExportError: LocalizedError, Equatable {
        case sourceUnavailable
        case chapterFileNotFound(Int)
        case noAudioTrack(URL)
        case readFailed(String)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .sourceUnavailable:
                return "The book's audio file is missing."
            case .chapterFileNotFound(let number):
                return "No audio file for chapter \(number)."
            case .noAudioTrack(let url):
                return "No audio track in \(url.lastPathComponent)."
            case .readFailed(let reason):
                return "Could not read the chapter audio: \(reason)"
            case .writeFailed(let reason):
                return "Could not write the chapter audio: \(reason)"
            }
        }
    }

    /// Transcodes `source` into an `.m4a` at `outputURL`, replacing whatever is there.
    static func export(_ source: ExportSource, to outputURL: URL) async throws {
        let asset = AVURLAsset(url: source.fileURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ExportError.noAudioTrack(source.fileURL)
        }
        let sampleRate = await sourceSampleRate(of: track)

        let (reader, output) = try makeReader(asset: asset, track: track, timeRange: source.timeRange)
        let (writer, input) = try makeWriter(at: outputURL, sampleRate: sampleRate)

        try start(reader: reader, writer: writer, at: source.timeRange?.start ?? .zero)
        try pump(from: output, into: input, reader: reader, writer: writer)
        await writer.finishWriting()

        if let error = writer.error {
            throw ExportError.writeFailed(error.localizedDescription)
        }
        Log.sync.info("🎧 Exported chapter audio (\(sampleRate, privacy: .public) Hz mono AAC)")
    }

    // MARK: - Pieces

    /// 44.1 kHz unless the source is already below it — upsampling only costs bytes.
    private static func sourceSampleRate(of track: AVAssetTrack) async -> Double {
        let target: Double = 44_100
        guard let descriptions = try? await track.load(.formatDescriptions),
              let description = descriptions.first,
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              basic.mSampleRate > 0 else {
            return target
        }
        return min(basic.mSampleRate, target)
    }

    private static func makeReader(
        asset: AVURLAsset,
        track: AVAssetTrack,
        timeRange: CMTimeRange?
    ) throws -> (AVAssetReader, AVAssetReaderTrackOutput) {
        let reader = try AVAssetReader(asset: asset)
        if let timeRange {
            reader.timeRange = timeRange
        }
        // Linear PCM at one channel: AVFoundation does the downmix on the way out.
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1
        ])
        guard reader.canAdd(output) else { throw ExportError.readFailed("output rejected") }
        reader.add(output)
        return (reader, output)
    }

    private static func makeWriter(
        at outputURL: URL,
        sampleRate: Double
    ) throws -> (AVAssetWriter, AVAssetWriterInput) {
        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000
        ])
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw ExportError.writeFailed("input rejected") }
        writer.add(input)
        return (writer, input)
    }

    private static func start(reader: AVAssetReader, writer: AVAssetWriter, at time: CMTime) throws {
        guard writer.startWriting() else {
            throw ExportError.writeFailed(writer.error?.localizedDescription ?? "startWriting failed")
        }
        writer.startSession(atSourceTime: time)
        guard reader.startReading() else {
            throw ExportError.readFailed(reader.error?.localizedDescription ?? "startReading failed")
        }
    }

    /// Pulls the whole thing through synchronously. The alternative,
    /// `requestMediaDataWhenReady(on:using:)`, hands a `@Sendable` block non-`Sendable`
    /// AVFoundation objects, which Swift 6 rightly refuses; this runs off the main actor
    /// anyway and the writer applies its own back-pressure.
    private static func pump(
        from output: AVAssetReaderTrackOutput,
        into input: AVAssetWriterInput,
        reader: AVAssetReader,
        writer: AVAssetWriter
    ) throws {
        while let buffer = output.copyNextSampleBuffer() {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.005)
            }
            guard input.append(buffer) else {
                reader.cancelReading()
                input.markAsFinished()
                throw ExportError.writeFailed(writer.error?.localizedDescription ?? "append failed")
            }
        }
        input.markAsFinished()
        guard reader.status != .failed else {
            throw ExportError.readFailed(reader.error?.localizedDescription ?? "read failed")
        }
    }
}
