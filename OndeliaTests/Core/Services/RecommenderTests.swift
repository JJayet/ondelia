import Foundation
import Testing
@testable import Isora

@Suite("Recommendations")
@MainActor
struct RecommenderTests {
    private func item(_ id: String, _ title: String, author: String, series: String = "", genres: [String] = []) throws -> AudiobookShelfAPI.Item {
        let genres = genres.map { "\"\($0)\"" }.joined(separator: ",")
        let json = #"{"id":"\#(id)","media":{"metadata":{"title":"\#(title)","authorName":"\#(author)","seriesName":"\#(series)","description":"<p>A <b>blurb</b></p>","genres":[\#(genres)]}}}"#
        return try JSONDecoder().decode(AudiobookShelfAPI.Item.self, from: Data(json.utf8))
    }

    private func book(_ title: String, author: String = "Pierce Brown", at position: Double = 0, finished: Bool = false, played: Double = 0) -> AudiobookModel {
        let book = AudiobookModel(title: title, author: author, duration: 36_000, currentPosition: position, isFinished: finished)
        book.lastPlayed = Date(timeIntervalSince1970: played)
        return book
    }

    @Test("A two-minute sample is neither history nor a book to continue")
    func samples() {
        let sampled = book("The Final Empire", author: "Brandon Sanderson", at: 120, played: 200)
        let listened = book("Iron Gold", at: 9_000, played: 100)

        let history = Recommender.history([sampled, listened])

        #expect(history.map(\.title) == ["Iron Gold"])
        #expect(Recommender.resume(history)?.candidate.title == "Iron Gold")
    }

    @Test("Next in a series: the volume after the furthest finished one, never an earlier one")
    func nextInSeries() {
        let first = book("Red Rising")
        let second = book("Golden Son", finished: true, played: 100)
        let third = book("Morning Star")
        let series = CollectionModel(name: "Red Rising", hardcoverSeriesID: 7, bookIDs: [first.id, second.id, third.id])

        let pick = Recommender.nextInSeries(books: [first, second, third], collections: [series])

        #expect(pick?.candidate.title == "Morning Star")
        #expect(pick?.kind == .nextInSeries)
    }

    @Test("A series whose furthest volume is underway has no next pick: that is the book to continue")
    func seriesUnderway() {
        let second = book("Golden Son", finished: true, played: 100)
        let third = book("Morning Star", at: 9_000, played: 200)
        let fourth = book("Iron Gold")
        let series = CollectionModel(name: "Red Rising", hardcoverSeriesID: 7, bookIDs: [second.id, third.id, fourth.id])

        #expect(Recommender.nextInSeries(books: [second, third, fourth], collections: [series]) == nil)
    }

    @Test("Something different: none of the history's authors or series, nothing started")
    func differentShortlist() throws {
        let listened = book("Leviathan Wakes", author: "James S. A. Corey", at: 9_000)
        let sampled = book("The Final Empire", author: "Brandon Sanderson", at: 120)
        let series = CollectionModel(name: "The Expanse", hardcoverSeriesID: 3, bookIDs: [listened.id])
        let server = [
            try item("1", "Dune", author: "Frank Herbert"),
            try item("2", "Memory's Legion", author: "James S. A. Corey"),
            try item("3", "Tiamat's Wrath", author: "Someone Else", series: "The Expanse #8"),
            try item("4", "The Final Empire [Abridged]", author: "Brandon Sanderson, GraphicAudio"),
        ]

        let shortlist = Recommender.differentShortlist(
            books: [listened, sampled],
            collections: [series],
            server: server,
            excluding: []
        )

        #expect(shortlist.map(\.id) == ["1"])
    }

    @Test("The prompt shows how far each book got and strips the blurb's HTML")
    func prompt() throws {
        let played = AudiobookModel(title: "Leviathan Wakes", author: "James S. A. Corey", duration: 4000, currentPosition: 1000)
        let candidate = Recommender.Candidate(try item("1", "Dune", author: "Frank Herbert", genres: ["Sci-Fi"]))

        let prompt = Recommender.prompt(history: [played], shortlist: [candidate])

        #expect(prompt.contains("- Leviathan Wakes by James S. A. Corey (25% listened)"))
        #expect(prompt.contains("1. Dune by Frank Herbert [Sci-Fi]: "))
        #expect(!prompt.contains("<b>"))
    }

    @Test("Too few books by other authors: the history's authors fill the shortlist after them")
    func authorsLetBackIn() throws {
        let listened = book("Leviathan Wakes", author: "James S. A. Corey", at: 9_000)
        let server = [try item("1", "Dune", author: "Frank Herbert"), try item("2", "Memory's Legion", author: "James S. A. Corey")]

        let shortlist = Recommender.differentShortlist(books: [listened], collections: [], server: server, excluding: [], atLeast: 2)

        #expect(shortlist.map(\.id) == ["1", "2"])
    }

    @Test("Nothing to continue and no series: three picks, even without the model's")
    func alwaysThree() async throws {
        let finished = book("Leviathan Wakes", author: "James S. A. Corey", finished: true)
        let server = try (1...5).map { try item("\($0)", "Book \($0)", author: "Author \($0)") }

        let picks = try await Recommender.recommend(books: [finished], collections: [], server: server)

        #expect(picks.count == 3)
        #expect(Set(picks.map(\.id)).count == 3)
    }
}
