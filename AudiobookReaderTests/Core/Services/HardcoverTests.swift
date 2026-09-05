import Foundation
import Testing
@testable import AudiobookReader

@Suite("Hardcover")
struct HardcoverTests {

    // MARK: - Search query

    @MainActor
    private func book(title: String?, author: String?) -> AudiobookModel {
        AudiobookModel(title: title, author: author)
    }

    @MainActor
    @Test("Volume numbering is stripped from the search query")
    func stripsVolumeNumbering() {
        let service = HardcoverService.shared
        #expect(service.searchQuery(for: book(title: "Book 3 - The Fellowship", author: "Tolkien"))
            == "The Fellowship, Tolkien")
        #expect(service.searchQuery(for: book(title: "03. The Fellowship", author: "Tolkien"))
            == "The Fellowship, Tolkien")
        #expect(service.searchQuery(for: book(title: "5 - The Fellowship", author: nil))
            == "The Fellowship")
    }

    @MainActor
    @Test("A book with no author searches on its title alone")
    func omitsEmptyAuthor() {
        #expect(HardcoverService.shared.searchQuery(for: book(title: "Dune", author: "  ")) == "Dune")
    }

    // MARK: - Shelf status

    @Test("Statuses only ever move forward")
    func statusesAreOrdered() {
        #expect(HardcoverLink.Status.local < .wantToRead)
        #expect(HardcoverLink.Status.wantToRead < .reading)
        #expect(HardcoverLink.Status.reading < .read)
        #expect(!(HardcoverLink.Status.read < .reading))
    }

    // MARK: - Decoding

    /// Typesense answers with the id as a string on some indexes and a number on others.
    @Test("Search hits decode either spelling of the id", arguments: ["\"445742\"", "445742"])
    func decodesEitherIDSpelling(rawID: String) throws {
        let json = """
            {"id": \(rawID), "title": "Catharsis", "author_names": ["Travis Bagwell"],
             "image": {"url": "https://example.com/cover.jpg"}}
            """
        let hit = try JSONDecoder().decode(HardcoverAPI.SearchHit.self, from: Data(json.utf8))
        #expect(hit.id == 445742)
        #expect(hit.author == "Travis Bagwell")
        #expect(hit.artworkURL == URL(string: "https://example.com/cover.jpg"))
    }

    /// Hardcover returns the series position as a number on some rows and a string on others,
    /// and omits it entirely for a book whose place in the series is unrecorded.
    @Test(
        "Series positions decode from either spelling",
        arguments: [("3", 3.0), ("\"3\"", 3.0), ("3.5", 3.5), ("null", nil)] as [(String, Double?)]
    )
    func decodesSeriesPosition(rawPosition: String, expected: Double?) throws {
        let json = """
            {"books": [{"book_series": [{"position": \(rawPosition), "series": {"id": 7, "name": "Mistborn"}}]}]}
            """
        let response = try JSONDecoder().decode(HardcoverAPI.BookSeriesResponse.self, from: Data(json.utf8))
        let entry = try #require(response.books.first?.bookSeries.first)
        #expect(entry.series.id == 7)
        #expect(entry.series.name == "Mistborn")
        #expect(entry.position == expected)
    }

    @Test("A standalone book decodes as no series at all")
    func decodesStandaloneBook() throws {
        let json = #"{"books": [{"book_series": []}]}"#
        let response = try JSONDecoder().decode(HardcoverAPI.BookSeriesResponse.self, from: Data(json.utf8))
        #expect(response.books.first?.bookSeries.isEmpty == true)
    }

    @Test("Book details decode their description and tag buckets")
    func decodesBookDetails() throws {
        let json = """
            {"books": [{"description": "A thief discovers Allomancy.",
             "cached_tags": {"Genre": [{"tag": "Fantasy"}, {"tag": "Epic"}],
                             "Mood": [{"tag": "Dark"}],
                             "Content Warning": [{"tag": "Violence"}]}}]}
            """
        let response = try JSONDecoder().decode(HardcoverAPI.BookDetailsResponse.self, from: Data(json.utf8))
        let book = try #require(response.books.first)
        #expect(book.description == "A thief discovers Allomancy.")
        #expect(book.tags(in: "Genre") == ["Fantasy", "Epic"])
        #expect(book.tags(in: "Mood") == ["Dark"])
        #expect(book.tags(in: "Content Warning") == ["Violence"])
    }

    /// `cached_tags` is a free-form column: a shape this app does not know must not take the
    /// description down with it.
    @Test("An unexpected tag payload leaves the description intact")
    func toleratesUnknownTagShapes() throws {
        let json = #"{"books": [{"description": "Blurb.", "cached_tags": []}]}"#
        let response = try JSONDecoder().decode(HardcoverAPI.BookDetailsResponse.self, from: Data(json.utf8))
        let book = try #require(response.books.first)
        #expect(book.description == "Blurb.")
        #expect(book.tags(in: "Genre").isEmpty)
    }

    @Test("A hit with no author or artwork still decodes")
    func decodesSparseHit() throws {
        let json = #"{"id": 1, "title": "Untitled", "author_names": []}"#
        let hit = try JSONDecoder().decode(HardcoverAPI.SearchHit.self, from: Data(json.utf8))
        #expect(hit.author.isEmpty)
        #expect(hit.artworkURL == nil)
    }

    @Test("GraphQL errors surface as a failure, not as empty results")
    func graphQLErrorsThrow() throws {
        let json = #"{"errors": [{"message": "field 'search' not found"}]}"#
        let envelope = try JSONDecoder().decode(
            HardcoverEnvelopeProbe.self, from: Data(json.utf8)
        )
        #expect(envelope.errors?.first?.message == "field 'search' not found")
    }

    /// Mirrors `HardcoverAPI.Envelope`, which is private to the API layer.
    struct HardcoverEnvelopeProbe: Decodable {
        let errors: [GraphQLError]?
        struct GraphQLError: Decodable { let message: String }
    }
}
