import Foundation
import Testing
@testable import Isora

@Suite("Watch transfer queue")
@MainActor
struct WatchTransferQueueTests {

    /// A throwaway suite per test, so nothing lands in the app's real defaults.
    private func makeDefaults() throws -> UserDefaults {
        let name = "watch-queue-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("The window starts at the current chapter")
    func windowAtStart() {
        #expect(WatchTransferQueue.desiredWindow(currentChapter: 1, chapterCount: 20) == [1, 2, 3])
    }

    @Test("The window follows the listener through the book")
    func windowInMiddle() {
        #expect(WatchTransferQueue.desiredWindow(currentChapter: 9, chapterCount: 20) == [9, 10, 11])
    }

    @Test("The window is clamped at the end of the book")
    func windowAtEnd() {
        #expect(WatchTransferQueue.desiredWindow(currentChapter: 19, chapterCount: 20) == [19, 20])
        #expect(WatchTransferQueue.desiredWindow(currentChapter: 20, chapterCount: 20) == [20])
    }

    @Test("A width other than three, and degenerate books")
    func windowEdges() {
        #expect(WatchTransferQueue.desiredWindow(currentChapter: 2, chapterCount: 10, width: 1) == [2])
        #expect(WatchTransferQueue.desiredWindow(currentChapter: 0, chapterCount: 5) == [1, 2, 3])
        #expect(WatchTransferQueue.desiredWindow(currentChapter: 99, chapterCount: 5) == [5])
        #expect(WatchTransferQueue.desiredWindow(currentChapter: 1, chapterCount: 0).isEmpty)
    }

    @Test("What is already on the watch is not sent again, but a request always is")
    func windowSkipsWhatTheWatchHolds() {
        #expect(
            WatchTransferQueue.chaptersToSend(currentChapter: 4, chapterCount: 20, alreadyOnWatch: [5]) == [4, 6]
        )
        // The watch only asks for a chapter it does not have; a stale inventory must not win.
        #expect(
            WatchTransferQueue.chaptersToSend(currentChapter: 4, chapterCount: 20, alreadyOnWatch: [4, 5, 6]) == [4]
        )
        #expect(
            WatchTransferQueue.chaptersToSend(currentChapter: 1, chapterCount: 20, alreadyOnWatch: []) == [1, 2, 3]
        )
    }

    @Test("A chapter that failed is queued again rather than skipped")
    func enqueueRetriesFailures() throws {
        let queue = WatchTransferQueue(defaults: try makeDefaults())
        let bookID = UUID()
        queue.enqueue(bookID: bookID, chapters: [1])
        let item = try #require(queue.next())
        queue.update(item, state: .failed("export died"))
        #expect(queue.next() == nil)

        queue.enqueue(bookID: bookID, chapters: [1])

        #expect(queue.pending.count == 1)
        #expect(queue.next()?.chapterNumber == 1)
    }

    @Test("Enqueuing the same chapter twice tracks it once")
    func enqueueDeduplicates() throws {
        let queue = WatchTransferQueue(defaults: try makeDefaults())
        let bookID = UUID()

        queue.enqueue(bookID: bookID, chapters: [1, 2, 3])
        queue.enqueue(bookID: bookID, chapters: [2, 3, 4])

        #expect(queue.pending.map(\.chapterNumber) == [1, 2, 3, 4])
    }

    @Test("The same chapter number of another book is a different item")
    func enqueueSeparatesBooks() throws {
        let queue = WatchTransferQueue(defaults: try makeDefaults())
        let first = UUID()
        let second = UUID()

        queue.enqueue(bookID: first, chapters: [1])
        queue.enqueue(bookID: second, chapters: [1])

        #expect(queue.pending.count == 2)
    }

    @Test("next() hands out the oldest untouched chapter")
    func nextSkipsWorkInFlight() throws {
        let queue = WatchTransferQueue(defaults: try makeDefaults())
        let bookID = UUID()
        queue.enqueue(bookID: bookID, chapters: [1, 2])

        let first = try #require(queue.next())
        #expect(first.chapterNumber == 1)

        queue.update(first, state: .exporting)
        #expect(queue.next()?.chapterNumber == 2)
    }

    @Test("Removing and clearing drop the right rows")
    func removeAndClear() throws {
        let queue = WatchTransferQueue(defaults: try makeDefaults())
        let first = UUID()
        let second = UUID()
        queue.enqueue(bookID: first, chapters: [1, 2])
        queue.enqueue(bookID: second, chapters: [1])

        queue.remove(bookID: first, chapterNumber: 1)
        #expect(queue.pending.map(\.chapterNumber) == [2, 1])

        queue.clear(bookID: first)
        #expect(queue.pending.count == 1)
        #expect(queue.pending.first?.bookID == second)
    }

    @Test("The queue and its states survive a relaunch")
    func persistenceRoundTrip() throws {
        let defaults = try makeDefaults()
        let bookID = UUID()

        let queue = WatchTransferQueue(defaults: defaults)
        queue.enqueue(bookID: bookID, chapters: [4, 5, 6])
        let exporting = try #require(queue.next())
        queue.update(exporting, state: .sending(fraction: 0.42))
        queue.update(
            WatchTransferQueue.PendingChapter(bookID: bookID, chapterNumber: 5),
            state: .failed("no space")
        )

        let reloaded = WatchTransferQueue(defaults: defaults)
        #expect(reloaded.pending.count == 3)
        #expect(reloaded.pending[0].state == .sending(fraction: 0.42))
        #expect(reloaded.pending[1].state == .failed("no space"))
        #expect(reloaded.pending[2].state == .queued)
        #expect(reloaded.next()?.chapterNumber == 6)
    }
}
