import Foundation
import Testing
@testable import Isora

@MainActor
@Suite("Continue Reading entries")
struct ContinueReadingEntryTests {
    private func book(_ title: String, at seconds: Double, playedAgo: TimeInterval) -> AudiobookModel {
        AudiobookModel(
            title: title,
            duration: 3600,
            currentPosition: seconds,
            lastPlayed: Date().addingTimeInterval(-playedAgo)
        )
    }

    @Test("A book in a collection is shown as the collection, once, for its latest volume")
    func collectionsFold() {
        let one = book("One", at: 3600, playedAgo: 300)
        let two = book("Two", at: 100, playedAgo: 10)
        let lone = book("Lone", at: 50, playedAgo: 100)
        let unread = book("Unread", at: 0, playedAgo: 1)
        one.isFinished = true
        let series = CollectionModel(name: "Series", bookIDs: [one.id, two.id])

        let entries = ContinueReadingEntry.build(
            books: [one, two, lone, unread],
            collections: [series],
            orderedBooks: { _ in [one, two] }
        )

        #expect(entries.count == 2)
        guard case .collection(let group, let current) = entries[0] else {
            Issue.record("expected the series first")
            return
        }
        #expect(group.id == series.id)
        #expect(current.id == two.id)
        #expect(entries[0].book.id == two.id)
        #expect(entries[1].book.id == lone.id)
    }

    @Test("Two volumes in progress in one collection make one card")
    func oneCardPerCollection() {
        let one = book("One", at: 10, playedAgo: 10)
        let two = book("Two", at: 10, playedAgo: 20)
        let series = CollectionModel(name: "Series", bookIDs: [one.id, two.id])

        let entries = ContinueReadingEntry.build(
            books: [one, two],
            collections: [series],
            orderedBooks: { _ in [one, two] }
        )

        #expect(entries.count == 1)
        #expect(entries[0].book.id == one.id)
    }
}
