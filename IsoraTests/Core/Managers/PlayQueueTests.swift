import Testing
import Foundation
@testable import Isora

@MainActor
struct PlayQueueTests {
    let suiteName = "PlayQueueTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let queue: PlayQueue

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        queue = PlayQueue(defaults: defaults)
    }

    private func book(_ title: String) -> AudiobookModel {
        AudiobookModel(title: title, duration: 3600)
    }

    @Test("append ignores a book already queued")
    func appendNoDuplicates() {
        let dune = book("Dune")
        let neuromancer = book("Neuromancer")
        queue.append(dune)
        queue.append(dune)
        queue.append(neuromancer)
        #expect(queue.bookIDs == [dune.id, neuromancer.id])
    }

    @Test("toggle appends then removes")
    func toggleAddsAndRemoves() {
        let dune = book("Dune")
        queue.toggle(dune)
        #expect(queue.contains(dune))
        queue.toggle(dune)
        #expect(queue.contains(dune) == false)
        #expect(queue.bookIDs.isEmpty)
    }

    @Test("move reorders the queue")
    func moveReorders() {
        let books = [book("A"), book("B"), book("C")]
        for book in books { queue.append(book) }
        queue.move(fromOffsets: [2], toOffset: 0)
        #expect(queue.bookIDs == [books[2].id, books[0].id, books[1].id])
    }

    @Test("books(in:) skips ids missing from the library without touching the queue")
    func booksSkipsStaleIDs() {
        let kept = book("Kept")
        let gone = book("Gone")
        queue.append(gone)
        queue.append(kept)
        #expect(queue.books(in: [kept]).map(\.id) == [kept.id])
        #expect(queue.bookIDs == [gone.id, kept.id])
    }

    @Test("popNext returns the head and skips stale ids")
    func popNextSkipsStale() {
        let gone = book("Gone")
        let next = book("Next")
        queue.append(gone)
        queue.append(next)

        #expect(queue.popNext(from: [next])?.id == next.id)
        #expect(queue.bookIDs.isEmpty)
        #expect(queue.popNext(from: [next]) == nil)
    }

    @Test("the queue survives a new instance on the same defaults")
    func persistenceRoundTrip() throws {
        let first = book("First")
        let second = book("Second")
        queue.append(first)
        queue.append(second)

        let reloaded = PlayQueue(defaults: try #require(UserDefaults(suiteName: suiteName)))
        #expect(reloaded.bookIDs == [first.id, second.id])
    }
}
