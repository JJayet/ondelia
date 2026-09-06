import AVFoundation
import Foundation
import Testing
@testable import Isora

/// The exporter is the one piece that has to be right before a byte leaves the phone: the watch
/// gets mono AAC or it gets a file it cannot afford. Run against a generated sine so there is
/// no fixture to keep in the repo.
@Suite("Watch audio exporter")
struct WatchAudioExporterTests {

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Three seconds of a 440 Hz sine, stereo, 44.1 kHz.
    private func writeSine(to url: URL, seconds: Double = 3) throws {
        let sampleRate = 44_100.0
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(sampleRate * seconds)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames

        let channels = try #require(buffer.floatChannelData)
        for frame in 0..<Int(frames) {
            let value = Float(sin(2 * Double.pi * 440 * Double(frame) / sampleRate)) * 0.5
            for channel in 0..<Int(format.channelCount) {
                channels[channel][frame] = value
            }
        }
        try file.write(from: buffer)
    }

    private func audioTrackChannelCount(of url: URL) async throws -> UInt32? {
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let description = try #require(try await track.load(.formatDescriptions).first)
        return CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee.mChannelsPerFrame
    }

    @Test("A chapter of a single-file book is cut to its time range")
    func exportsTimeRange() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("book.caf")
        let output = directory.appendingPathComponent("chapter.m4a")
        try writeSine(to: source)

        let range = CMTimeRange(
            start: CMTime(seconds: 1.0, preferredTimescale: 600),
            end: CMTime(seconds: 2.5, preferredTimescale: 600)
        )
        try await WatchAudioExporter.export(
            .init(fileURL: source, timeRange: range),
            to: output
        )

        #expect(FileManager.default.fileExists(atPath: output.path))
        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 1.5) < 0.2)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        #expect(tracks.count == 1)
        #expect(try await audioTrackChannelCount(of: output) == 1)
    }

    @Test("A chapter of a folder book is the whole file")
    func exportsWholeFile() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("chapter-01.caf")
        let output = directory.appendingPathComponent("chapter-01.m4a")
        try writeSine(to: source)

        try await WatchAudioExporter.export(.init(fileURL: source), to: output)

        let duration = try await AVURLAsset(url: output).load(.duration).seconds
        #expect(abs(duration - 3.0) < 0.2)
        #expect(try await audioTrackChannelCount(of: output) == 1)
    }

    @Test("An existing output file is replaced, not appended to")
    func overwritesOutput() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("book.caf")
        let output = directory.appendingPathComponent("chapter.m4a")
        try writeSine(to: source, seconds: 1)
        try Data("stale".utf8).write(to: output)

        try await WatchAudioExporter.export(.init(fileURL: source), to: output)

        let duration = try await AVURLAsset(url: output).load(.duration).seconds
        #expect(abs(duration - 1.0) < 0.2)
    }

    @Test("A file with no audio track throws rather than writing something unplayable")
    func rejectsNonAudio() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("not-audio.m4a")
        try Data("definitely not audio".utf8).write(to: source)

        await #expect(throws: (any Error).self) {
            try await WatchAudioExporter.export(
                .init(fileURL: source),
                to: directory.appendingPathComponent("out.m4a")
            )
        }
    }
}
