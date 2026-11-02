import Foundation
import Testing
@testable import Isora

/// The playback position reaching the library: on the save timer while a book plays, and on
/// the write the app makes when it leaves the foreground (`persistProgress`, called from
/// `IsoraApp.handleAppWillResignActive`).
@MainActor
@Suite("GlobalAudioManager progress saving", .serialized)
struct GlobalAudioManagerProgressTests {
    private let manager = GlobalAudioManager.shared

    /// The fixture, playing, past its first half second.
    private func playingBook() async throws -> AudiobookModel {
        await AudiobookManager.shared.swiftDataController.whenLoaded()
        let book = try await loadFixtureBook(into: manager)
        manager.resumePlayback()
        try #require(await waitUntil(timeout: 5) { manager.getCurrentTime() > 0.5 })
        return book
    }

    @Test("A playing book writes its position on the save timer")
    func saveTimerWritesPosition() async throws {
        let book = try await playingBook()
        defer { manager.unload() }
        #expect(book.currentPosition == 0)

        let timer = try #require(manager.progressTimer)
        #expect(timer.timeInterval == 5)
        timer.fire()

        #expect(await waitUntil { book.currentPosition > 0.4 })
        // Still playing: this is the timer's write, not the one pausing makes.
        #expect(manager.playbackState == .playing)
    }

    @Test("The save timer runs only while playing")
    func saveTimerStopsOnPause() async throws {
        _ = try await playingBook()
        defer { manager.unload() }
        #expect(manager.progressTimer != nil)

        manager.pausePlayback()

        #expect(manager.progressTimer == nil)
    }

    @Test("Leaving the foreground writes the position the book is at")
    func backgroundingWritesPosition() async throws {
        let book = try await playingBook()
        defer { manager.unload() }

        manager.persistProgress()

        #expect(abs(book.currentPosition - manager.getCurrentTime()) < 0.3)
        #expect(book.currentPosition > 0.4)
        #expect(book.positionUpdatedAt != nil)
    }

    @Test("A book still loading does not overwrite its saved position with zero")
    func loadingBookKeepsSavedPosition() async throws {
        let book = try await loadFixtureBook(into: manager)
        defer { manager.unload() }
        book.currentPosition = 1.5
        manager.isLoading = true

        manager.persistProgress()

        #expect(book.currentPosition == 1.5)
        manager.isLoading = false
    }

    @Test("Opening another book stops the last one's save timer")
    func loadingAnotherBookStopsSaveTimer() async throws {
        _ = try await playingBook()
        defer { manager.unload() }
        #expect(manager.progressTimer != nil)

        manager.loadAudiobook(AudiobookModel(title: "Next", duration: 3600))

        #expect(manager.progressTimer == nil)
    }

    @Test("Playing a finished book again starts it from the beginning")
    func finishedBookReplaysFromStart() async throws {
        let book = try await loadFixtureBook(into: manager)
        defer { manager.unload() }
        book.isFinished = true
        manager.player?.seek(to: manager.getDuration() - 0.5)

        manager.resumePlayback()

        #expect(manager.getCurrentTime() < 0.5)
        #expect(!book.isFinished)
    }

    @Test("An end-of-chapter sleep timer reaching the end of the book stops there, queue or not")
    func endOfChapterSleepStopsAtBookEnd() async throws {
        let book = try await loadFixtureBook(into: manager)
        // Already finished, so the end logs no Finish and leaves the library as it is.
        book.isFinished = true
        let next = AudiobookModel(title: "Queued", duration: 3600)
        let library = AudiobookManager.shared
        library.audiobooks.append(next)
        PlayQueue.shared.append(next)
        defer {
            PlayQueue.shared.remove(next)
            library.audiobooks.removeAll { $0.id == next.id }
            manager.unload()
        }
        manager.sleepChapterEnd = manager.getDuration()

        manager.player?.onPlaybackEnded?()

        #expect(manager.sleepChapterEnd == nil)
        #expect(manager.currentAudiobook?.id == book.id)
        #expect(PlayQueue.shared.contains(next))
    }
}
