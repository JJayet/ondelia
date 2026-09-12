import Foundation
import Testing
@testable import Isora

/// The two rules the sync service has that are worth pinning down without a `WCSession`:
/// which books reach the snapshot, and which position write wins.
@Suite("Watch sync rules")
@MainActor
struct WatchSyncServiceTests {

    private func book(
        _ title: String,
        lastPlayed: TimeInterval,
        finished: Bool = false
    ) -> AudiobookModel {
        let model = AudiobookModel(
            title: title,
            duration: 3_600,
            lastPlayed: Date(timeIntervalSince1970: lastPlayed)
        )
        model.isFinished = finished
        return model
    }

    // MARK: - Book selection

    @Test("The three most recently played unfinished books, newest first")
    func picksRecentUnfinishedBooks() {
        let library = [
            book("Newest", lastPlayed: 400),
            book("Middle", lastPlayed: 300),
            book("Older", lastPlayed: 200),
            book("Oldest", lastPlayed: 100)
        ]

        let picked = WatchSyncService.selectBooks(from: library, onWatch: [])

        #expect(picked.map { $0.title } == ["Newest", "Middle", "Older"])
    }

    @Test("Finished books never take a slot")
    func skipsFinishedBooks() {
        let library = [
            book("Done", lastPlayed: 500, finished: true),
            book("Newest", lastPlayed: 400),
            book("Middle", lastPlayed: 300),
            book("Older", lastPlayed: 200)
        ]

        let picked = WatchSyncService.selectBooks(from: library, onWatch: [])

        #expect(picked.map { $0.title } == ["Newest", "Middle", "Older"])
    }

    @Test("A book with content on the watch comes first, however old it is")
    func watchContentWinsTheFirstSlot() {
        let held = book("On the watch", lastPlayed: 1)
        let library = [
            book("Newest", lastPlayed: 400),
            book("Middle", lastPlayed: 300),
            book("Older", lastPlayed: 200),
            held
        ]

        let picked = WatchSyncService.selectBooks(from: library, onWatch: [held.id])

        #expect(picked.map { $0.title } == ["On the watch", "Newest", "Middle"])
    }

    @Test("Content on the watch keeps a finished book in the snapshot")
    func watchContentKeepsAFinishedBook() {
        let held = book("Finished but held", lastPlayed: 10, finished: true)
        let library = [held, book("Newest", lastPlayed: 400)]

        let picked = WatchSyncService.selectBooks(from: library, onWatch: [held.id])

        #expect(picked.map { $0.title } == ["Finished but held", "Newest"])
    }

    @Test("An empty library selects nothing")
    func emptyLibrary() {
        #expect(WatchSyncService.selectBooks(from: [], onWatch: []).isEmpty)
    }

    // MARK: - Last write wins

    @Test("A newer remote write wins")
    func newerRemoteWins() {
        let local = Date(timeIntervalSince1970: 1_000)
        #expect(WatchSyncService.shouldApply(remote: local.addingTimeInterval(1), localUpdatedAt: local))
    }

    @Test("An older or identical remote write loses")
    func olderRemoteLoses() {
        let local = Date(timeIntervalSince1970: 1_000)
        #expect(!WatchSyncService.shouldApply(remote: local.addingTimeInterval(-1), localUpdatedAt: local))
        #expect(!WatchSyncService.shouldApply(remote: local, localUpdatedAt: local))
    }

    @Test("A position written before the watch existed loses to anything")
    func nilLocalAlwaysLoses() {
        #expect(WatchSyncService.shouldApply(remote: .distantPast.addingTimeInterval(1), localUpdatedAt: nil))
    }
}
