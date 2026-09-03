import Foundation
import Testing
@testable import AudiobookReader

/// The timeline is the only thing `AudiobookPlayer` adds on top of `AVQueuePlayer`, so it is
/// the part worth testing without touching audio hardware.
@Suite("AudiobookPlayer timeline")
struct AudiobookPlayerTimelineTests {

    private func makeFolder(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("timeline-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeFile(_ name: String, in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data("not really audio".utf8).write(to: url)
        return url
    }

    private func writeManifest(_ chapters: [(String, TimeInterval)], in folder: URL) throws {
        let payload: [String: Any] = [
            "chapters": chapters.map { ["fileName": $0.0, "duration": $0.1] }
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: folder.appendingPathComponent("audiobook_manifest.json"))
    }

    @Test("Manifest durations become cumulative start offsets")
    func manifestBuildsCumulativeTimeline() async throws {
        let folder = try makeFolder("manifest")
        for name in ["01.m4a", "02.m4a", "03.m4a"] {
            _ = try writeFile(name, in: folder)
        }
        try writeManifest([("01.m4a", 100), ("02.m4a", 200), ("03.m4a", 50)], in: folder)

        let tracks = await AudiobookPlayer.makeTracks(at: folder, fallbackDuration: 0)

        #expect(tracks.count == 3)
        #expect(tracks.map(\.start) == [0, 100, 300])
        #expect(tracks.map(\.duration) == [100, 200, 50])
        #expect(tracks.last?.end == 350)
    }

    @Test("A chapter whose file is missing is left out and does not shift the rest")
    func missingChapterFileIsSkipped() async throws {
        let folder = try makeFolder("missing")
        _ = try writeFile("01.m4a", in: folder)
        _ = try writeFile("03.m4a", in: folder)
        try writeManifest([("01.m4a", 100), ("02.m4a", 200), ("03.m4a", 50)], in: folder)

        let tracks = await AudiobookPlayer.makeTracks(at: folder, fallbackDuration: 0)

        #expect(tracks.count == 2)
        #expect(tracks.map(\.url.lastPathComponent) == ["01.m4a", "03.m4a"])
        // The gap closes rather than leaving 200 s of silence nothing can play.
        #expect(tracks.map(\.start) == [0, 100])
    }

    @Test("A manifest entry cannot escape the book folder")
    func manifestCannotEscapeFolder() async throws {
        let folder = try makeFolder("escape")
        _ = try writeFile("01.m4a", in: folder)
        try writeManifest([("../../etc/passwd", 100), ("01.m4a", 50)], in: folder)

        let tracks = await AudiobookPlayer.makeTracks(at: folder, fallbackDuration: 0)

        #expect(tracks.count == 1)
        #expect(tracks.first?.url.lastPathComponent == "01.m4a")
    }

    @Test("A single file becomes a one-track timeline using the stored duration")
    func singleFileUsesFallbackDuration() async throws {
        let folder = try makeFolder("single")
        let file = try writeFile("book.m4a", in: folder)

        let tracks = await AudiobookPlayer.makeTracks(at: file, fallbackDuration: 1234)

        #expect(tracks == [AudiobookTrack(url: file, start: 0, duration: 1234)])
    }

    @Test("A path that does not exist yields no tracks")
    func missingPathYieldsNothing() async throws {
        let tracks = await AudiobookPlayer.makeTracks(
            at: URL(fileURLWithPath: "/nonexistent/book.m4a"),
            fallbackDuration: 100
        )
        #expect(tracks.isEmpty)
    }

    @Test("A folder with neither manifest nor readable audio yields no tracks")
    func unreadableFolderYieldsNothing() async throws {
        let folder = try makeFolder("empty")
        // Present but not decodable, so measuring its duration fails.
        _ = try writeFile("01.m4a", in: folder)

        let tracks = await AudiobookPlayer.makeTracks(at: folder, fallbackDuration: 500)

        #expect(tracks.isEmpty)
    }

    @Test("A position maps to the track that covers it")
    func positionMapsToTrack() async throws {
        let folder = try makeFolder("index")
        for name in ["01.m4a", "02.m4a", "03.m4a"] {
            _ = try writeFile(name, in: folder)
        }
        try writeManifest([("01.m4a", 100), ("02.m4a", 200), ("03.m4a", 50)], in: folder)
        let tracks = await AudiobookPlayer.makeTracks(at: folder, fallbackDuration: 0)

        func index(_ time: TimeInterval) -> Int {
            AudiobookPlayer.trackIndex(at: time, in: tracks)
        }

        #expect(tracks.last?.end == 350)
        #expect(index(0) == 0)
        #expect(index(99.9) == 0)
        #expect(index(100) == 1)        // exactly on a boundary
        #expect(index(299.9) == 1)
        #expect(index(300) == 2)
        #expect(index(-10) == 0)        // before the start
        #expect(index(10_000) == 2)     // past the end
    }

    @Test("A book whose stored duration is not a number yields no tracks")
    func nonFiniteStoredDurationIsRejected() async throws {
        let folder = try makeFolder("nan")
        let file = try writeFile("book.m4a", in: folder)

        // The file is not decodable, so the stored duration is the only candidate.
        for bad in [Double.nan, .infinity, -1, 0] {
            let tracks = await AudiobookPlayer.makeTracks(at: file, fallbackDuration: bad)
            #expect(tracks.isEmpty, "duration \(bad) should not produce a track")
        }
    }

    @Test("An empty timeline maps every position to zero instead of trapping")
    func emptyTimelineIsSafe() {
        #expect(AudiobookPlayer.trackIndex(at: 0, in: []) == 0)
        #expect(AudiobookPlayer.trackIndex(at: 500, in: []) == 0)
        #expect(AudiobookPlayer.trackIndex(at: -1, in: []) == 0)
    }
}
