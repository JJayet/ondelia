import Foundation
import AVFoundation
import Testing
@testable import Isora

/// Playback against the real 2.5 s AAC fixture (TestResources/SampleAudioFiles/sample.m4a).
/// Serialized because every suite in the process shares one AVAudioSession.
@Suite("AudiobookPlayer", .serialized)
@MainActor
struct AudiobookPlayerTests {

    private static let fixtureDuration: TimeInterval = 2.53

    private func fixtureURL() throws -> URL {
        try #require(Bundle(for: TestDataFactory.self).url(forResource: "sample", withExtension: "m4a"))
    }

    /// A book made of `count` copies of the fixture, with a manifest, so chapter crossing can
    /// be exercised without shipping a second fixture.
    private func multiChapterBook(count: Int) throws -> AudiobookModel {
        let source = try fixtureURL()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("book-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var entries: [[String: Any]] = []
        for index in 0..<count {
            let name = String(format: "%02d.m4a", index + 1)
            try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(name))
            entries.append(["fileName": name, "duration": Self.fixtureDuration])
        }
        let manifest = try JSONSerialization.data(withJSONObject: ["chapters": entries])
        try manifest.write(to: folder.appendingPathComponent("audiobook_manifest.json"))

        let book = AudiobookModel(title: "Multi", author: "Test", duration: Self.fixtureDuration * Double(count))
        book.fileURL = folder.path
        return book
    }

    private func singleFileBook() throws -> AudiobookModel {
        let book = AudiobookModel(title: "Single", author: "Test", duration: Self.fixtureDuration)
        book.fileURL = try fixtureURL().path
        return book
    }

    // MARK: - Defaults

    @Test("A fresh player is stopped and empty")
    func freshPlayerIsEmpty() {
        let player = AudiobookPlayer()
        #expect(player.isPlaying == false)
        #expect(player.currentTime == 0)
        #expect(player.duration == 0)
        #expect(player.playbackRate == 1)
        #expect(player.tracks.isEmpty)
        #expect(player.currentChapterIndex == 0)
    }

    @Test("Transport on an empty player does nothing rather than crashing")
    func emptyPlayerIgnoresTransport() {
        let player = AudiobookPlayer()
        player.play()
        player.seek(to: 100)
        player.skipForward(30)
        player.skipBackward(30)
        player.playChapter(at: 5)
        #expect(player.isPlaying == false)
        #expect(player.currentTime == 0)
    }

    // MARK: - Loading

    @Test("Loading a single-file book measures the file")
    func loadSingleFile() async throws {
        let player = AudiobookPlayer()
        #expect(await player.load(try singleFileBook()))
        #expect(player.tracks.count == 1)
        #expect(abs(player.duration - Self.fixtureDuration) < 0.3)
        #expect(player.currentTime == 0)
        #expect(player.isPlaying == false)
    }

    @Test("Loading a book whose file is gone reports failure")
    func loadMissingFile() async throws {
        let book = AudiobookModel(title: "Gone", author: "Test", duration: 100)
        book.fileURL = "/nonexistent/missing.m4a"

        let player = AudiobookPlayer()
        #expect(await player.load(book) == false)
        #expect(player.tracks.isEmpty)
        #expect(player.duration == 0)
    }

    @Test("Loading a folder book lays its chapters end to end")
    func loadMultiChapter() async throws {
        let player = AudiobookPlayer()
        #expect(await player.load(try multiChapterBook(count: 3)))
        #expect(player.tracks.count == 3)
        #expect(abs(player.duration - Self.fixtureDuration * 3) < 0.1)
        #expect(player.tracks[1].start > player.tracks[0].start)
    }

    // MARK: - Transport

    @Test("Play advances the position, pause stops it")
    func playAdvancesTime() async throws {
        let player = AudiobookPlayer()
        #expect(await player.load(try singleFileBook()))

        player.play()
        #expect(player.isPlaying)
        #expect(await waitUntil(timeout: 5) { player.currentTime > 0.2 })

        player.pause()
        #expect(player.isPlaying == false)
        let stopped = player.currentTime
        try await Task.sleep(for: .milliseconds(400))
        #expect(abs(player.currentTime - stopped) < 0.1)
    }

    @Test("Toggle flips between playing and paused")
    func toggleFlipsState() async throws {
        let player = AudiobookPlayer()
        #expect(await player.load(try singleFileBook()))

        player.togglePlayback()
        #expect(player.isPlaying)
        player.togglePlayback()
        #expect(player.isPlaying == false)
    }

    @Test("Seek moves the position and is clamped to the book")
    func seekMovesAndClamps() async throws {
        let player = AudiobookPlayer()
        #expect(await player.load(try singleFileBook()))

        player.seek(to: 1.5)
        #expect(abs(player.currentTime - 1.5) < 0.05)

        player.seek(to: -100)
        #expect(player.currentTime == 0)

        player.seek(to: 10_000)
        #expect(abs(player.currentTime - player.duration) < 0.05)
    }

    @Test("Skips move by the requested amount and stop at the edges")
    func skipsRespectEdges() async throws {
        let player = AudiobookPlayer()
        #expect(await player.load(try multiChapterBook(count: 3)))

        player.seek(to: 3)
        player.skipForward(2)
        #expect(abs(player.currentTime - 5) < 0.05)

        player.skipBackward(1)
        #expect(abs(player.currentTime - 4) < 0.05)

        player.skipBackward(500)
        #expect(player.currentTime == 0)

        player.skipForward(500)
        #expect(abs(player.currentTime - player.duration) < 0.05)
    }

    @Test("A seek to a non-finite position is ignored rather than trapping")
    func nonFiniteSeekIsIgnored() async throws {
        let player = AudiobookPlayer()
        #expect(await player.load(try singleFileBook()))

        player.seek(to: 1)
        let before = player.currentTime

        player.seek(to: .nan)
        player.seek(to: .infinity)
        player.seek(to: -.infinity)

        #expect(player.currentTime == before)
    }

    // MARK: - Chapters

    @Test("Seeking past a chapter boundary switches chapter and keeps book time")
    func seekCrossesChapters() async throws {
        let player = AudiobookPlayer()
        #expect(await player.load(try multiChapterBook(count: 3)))
        let secondChapterStart = player.tracks[1].start

        player.seek(to: secondChapterStart + 1)

        #expect(player.currentChapterIndex == 1)
        #expect(abs(player.currentTime - (secondChapterStart + 1)) < 0.05)

        // And back again: AVQueuePlayer only moves forwards, so this exercises the rebuild.
        player.seek(to: 0.5)
        #expect(player.currentChapterIndex == 0)
        #expect(abs(player.currentTime - 0.5) < 0.05)
    }

    @Test("playChapter lands on the start of that chapter")
    func playChapterJumpsToStart() async throws {
        let player = AudiobookPlayer()
        #expect(await player.load(try multiChapterBook(count: 3)))

        player.playChapter(at: 2)
        #expect(player.currentChapterIndex == 2)
        #expect(abs(player.currentTime - player.tracks[2].start) < 0.05)

        // Out of range is ignored rather than trapping.
        player.playChapter(at: 99)
        #expect(player.currentChapterIndex == 2)
    }

    @Test("The queue advances into the next chapter on its own")
    func queueAdvancesAcrossChapters() async throws {
        let player = AudiobookPlayer()
        #expect(await player.load(try multiChapterBook(count: 2)))

        // Start shortly before the end of chapter one and let AVQueuePlayer do the rest.
        player.seek(to: player.tracks[0].end - 0.4)
        player.play()

        #expect(await waitUntil(timeout: 8) { player.currentChapterIndex == 1 })
        #expect(player.currentTime > player.tracks[1].start - 0.2)
        player.pause()
    }

    @Test("Reaching the end of the last chapter reports the end of the book")
    func lastChapterEndReportsBookEnd() async throws {
        let player = AudiobookPlayer()
        #expect(await player.load(try multiChapterBook(count: 2)))
        var ended = 0
        player.onPlaybackEnded = { ended += 1 }

        player.seek(to: player.duration - 0.4)
        player.play()

        #expect(await waitUntil(timeout: 8) { ended == 1 })
        #expect(player.isPlaying == false)
        #expect(player.currentTime == player.duration)
    }

    // MARK: - Rate

    @Test("Playback rate is remembered and survives pause and resume")
    func rateSurvivesPauseResume() async throws {
        let player = AudiobookPlayer()
        #expect(await player.load(try singleFileBook()))

        // Set while paused: the old engines dropped this on the next play().
        player.setPlaybackRate(1.5)
        #expect(player.playbackRate == 1.5)
        #expect(player.isPlaying == false)

        player.play()
        #expect(await waitUntil { player.player.rate > 1.2 })

        player.pause()
        player.play()
        #expect(await waitUntil { player.player.rate > 1.2 })
        player.pause()
    }

    @Test("Rates that are not usable are rejected")
    func invalidRatesRejected() async throws {
        let player = AudiobookPlayer()
        #expect(await player.load(try singleFileBook()))

        player.setPlaybackRate(2)
        player.setPlaybackRate(0)
        player.setPlaybackRate(-1)
        player.setPlaybackRate(.nan)
        player.setPlaybackRate(.infinity)

        #expect(player.playbackRate == 2)
    }

    // MARK: - Teardown

    @Test("Tear down stops playback and empties the queue")
    func tearDownClears() async throws {
        let player = AudiobookPlayer()
        #expect(await player.load(try multiChapterBook(count: 2)))
        player.play()

        player.tearDown()

        #expect(player.isPlaying == false)
        #expect(player.tracks.isEmpty)
        #expect(player.duration == 0)
        #expect(player.currentTime == 0)
        #expect(player.player.items().isEmpty)
    }

    @Test("A torn-down player is released")
    func tearDownReleases() async throws {
        var player: AudiobookPlayer? = AudiobookPlayer()
        weak let weakPlayer = player
        #expect(await player?.load(try singleFileBook()) == true)

        player?.tearDown()
        player = nil

        #expect(await waitUntil { weakPlayer == nil })
    }
}
