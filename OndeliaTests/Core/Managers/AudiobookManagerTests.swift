import Testing
import Foundation
import SwiftData
@testable import Isora

@MainActor
struct AudiobookManagerTests {
    let controller = SwiftDataController.inMemory()
    let manager: AudiobookManager

    init() {
        manager = AudiobookManager(swiftDataController: controller)
    }

    /// Inserts a book backed by a real (empty) file so fetchAudiobooks keeps it.
    private func insertBook(title: String, duration: TimeInterval = 3600, lastPlayed: Date = .distantPast) -> AudiobookModel {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4b")
        FileManager.default.createFile(atPath: file.path, contents: Data())
        let book = AudiobookModel(title: title, fileURL: file.path, duration: duration, lastPlayed: lastPlayed)
        controller.context.insert(book)
        return book
    }

    @Test("updateProgress persists position and lastPlayed")
    func updateProgressPersists() throws {
        let book = insertBook(title: "Dune")
        manager.updateProgress(for: book, currentTime: 1200)

        let fetched = try controller.context.fetch(FetchDescriptor<AudiobookModel>())
        #expect(fetched.count == 1)
        #expect(fetched[0].currentPosition == 1200)
        #expect(fetched[0].lastPlayed > .distantPast)
        #expect(fetched[0].isFinished == false)
        #expect(controller.context.hasChanges == false)
    }

    @Test("updateProgress marks finished within 30s of the end, not before")
    func updateProgressMarksFinished() {
        let book = insertBook(title: "Dune", duration: 3600)
        manager.updateProgress(for: book, currentTime: 3569)
        #expect(book.isFinished == false)
        manager.updateProgress(for: book, currentTime: 3570)
        #expect(book.isFinished == true)
    }

    @Test("createBookmark links to the audiobook and deleteBookmark removes it")
    func bookmarkLifecycle() throws {
        let book = insertBook(title: "Dune")
        manager.createBookmark(for: book, at: 42, title: "Spice", note: "Fear is the mind-killer")

        let bookmarks = manager.getBookmarks(for: book)
        #expect(bookmarks.count == 1)
        #expect(bookmarks[0].timestamp == 42)
        #expect(bookmarks[0].title == "Spice")
        #expect(bookmarks[0].note == "Fear is the mind-killer")
        #expect(try controller.context.fetch(FetchDescriptor<BookmarkModel>()).count == 1)

        manager.deleteBookmark(bookmarks[0])
        #expect(try controller.context.fetch(FetchDescriptor<BookmarkModel>()).isEmpty)
        #expect(manager.getBookmarks(for: book).isEmpty)
    }

    @Test("markAsFinished / resetProgress toggle state")
    func markFinishedAndReset() {
        let book = insertBook(title: "Dune")
        manager.updateProgress(for: book, currentTime: 500)

        manager.markAsFinished(book)
        #expect(book.isFinished == true)

        manager.resetProgress(for: book)
        #expect(book.currentPosition == 0)
    }

    @Test("markAsRead sets position to end; markAsUnread clears finished")
    func markReadUnread() {
        let book = insertBook(title: "Dune", duration: 3600)
        manager.markAsRead(book)
        #expect(book.isFinished == true)
        #expect(book.currentPosition == 3600)

        manager.markAsUnread(book)
        #expect(book.isFinished == false)
    }

    @Test("fetchAudiobooks returns inserted models sorted by lastPlayed desc")
    func fetchSortedByLastPlayed() {
        let old = insertBook(title: "Old", lastPlayed: Date(timeIntervalSince1970: 1_000))
        let recent = insertBook(title: "Recent", lastPlayed: Date(timeIntervalSince1970: 3_000))
        let middle = insertBook(title: "Middle", lastPlayed: Date(timeIntervalSince1970: 2_000))

        manager.fetchAudiobooks()

        #expect(manager.audiobooks.map(\.title) == [recent.title, middle.title, old.title])
        #expect(manager.isLoadingLibrary == false)
    }

    @Test("fetchAudiobooks keeps books whose file is missing")
    func fetchKeepsMissingFiles() throws {
        // Deleting them threw away progress and bookmarks over a file that is often recoverable,
        // and the entry has to survive for a re-import to relink to it instead of duplicating.
        let present = insertBook(title: "Present")
        controller.context.insert(AudiobookModel(title: "Ghost", fileURL: "/nonexistent/ghost.m4b", duration: 10))

        manager.fetchAudiobooks()

        #expect(Set(manager.audiobooks.compactMap(\.title)) == ["Present", "Ghost"])
        #expect(try controller.context.fetch(FetchDescriptor<AudiobookModel>()).count == 2)
        #expect(manager.hasFile(present))
    }
}
