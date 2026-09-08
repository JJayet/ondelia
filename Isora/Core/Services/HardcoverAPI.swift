import Foundation

/// The slice of Hardcover's GraphQL API this app speaks: search for a book, put one on the
/// reader's shelf, take it off again.
///
/// No GraphQL client library and no `AnyCodable`: the three requests below only ever send
/// strings and ints, so `JSONSerialization` builds the body in one line.
enum HardcoverAPI {
    static let endpoint = URL(string: "https://api.hardcover.app/v1/graphql")!

    enum Failure: LocalizedError {
        case http(Int)
        case graphQL(String)
        case noData

        var errorDescription: String? {
            switch self {
            case .http(401), .http(403):
                return NSLocalizedString(
                    "Hardcover rejected the access token. Check it in Settings.",
                    comment: "Hardcover authentication failure"
                )
            case .http(let code):
                return String(
                    format: NSLocalizedString(
                        "Hardcover returned an error (%d).",
                        comment: "Hardcover HTTP failure, %d is the status code"
                    ),
                    code
                )
            case .graphQL(let message):
                return message
            case .noData:
                return NSLocalizedString(
                    "Hardcover returned no results.",
                    comment: "Hardcover empty response"
                )
            }
        }
    }

    static func execute<T: Decodable>(
        query: String,
        variables: [String: Any],
        token: String,
        as type: T.Type
    ) async throws -> T {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Tokens are handed out as a bare JWT on the Hardcover site, but the header wants the
        // scheme, so accept either spelling rather than making the reader get it right.
        request.setValue(
            token.lowercased().hasPrefix("bearer ") ? token : "Bearer \(token)",
            forHTTPHeaderField: "Authorization"
        )
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["query": query, "variables": variables]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw Failure.http(http.statusCode)
        }

        let envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        if let message = envelope.errors?.first?.message {
            throw Failure.graphQL(message)
        }
        guard let payload = envelope.data else { throw Failure.noData }
        return payload
    }

    private struct Envelope<T: Decodable>: Decodable {
        let data: T?
        let errors: [GraphQLError]?

        struct GraphQLError: Decodable {
            let message: String
        }
    }
}

// MARK: - Requests

extension HardcoverAPI {
    static func search(_ query: String, perPage: Int, token: String) async throws -> [SearchHit] {
        let document = searchBooksQuery
        let response = try await execute(
            query: document,
            variables: ["query": query, "per_page": perPage],
            token: token,
            as: SearchResponse.self
        )
        return response.search.results.hits.map(\.document)
    }

    /// Adds the book to the reader's shelf at `status`, returning the shelf row's id.
    static func setStatus(bookID: Int, status: HardcoverLink.Status, token: String) async throws -> Int {
        let document = insertUserBookMutation
        let response = try await execute(
            query: document,
            variables: ["book_id": bookID, "status_id": status.rawValue],
            token: token,
            as: InsertUserBookResponse.self
        )
        return response.insertUserBook.id
    }

    /// The series a book belongs to, or nil when Hardcover has it as a standalone.
    ///
    /// Search does not carry series, so this is a second request — made once per link, not per
    /// library read: the answer is stored on the link.
    static func series(bookID: Int, token: String) async throws -> SeriesRef? {
        let document = bookSeriesQuery
        let response = try await execute(
            query: document,
            variables: ["id": bookID],
            token: token,
            as: BookSeriesResponse.self
        )
        // A book can sit in several series (an omnibus, a shared universe). The first is the
        // one Hardcover shows on the book page, and grouping needs exactly one.
        guard let entry = response.books.first?.bookSeries.first else { return nil }
        return SeriesRef(id: entry.series.id, name: entry.series.name, position: entry.position)
    }

    /// What Hardcover knows about one book: its description, and the tags readers have put on
    /// it — genres, moods, content warnings.
    static func details(bookID: Int, token: String) async throws -> BookDetails? {
        let document = bookDetailsQuery
        let response = try await execute(
            query: document,
            variables: ["id": bookID],
            token: token,
            as: BookDetailsResponse.self
        )
        guard let book = response.books.first else { return nil }
        return BookDetails(
            summary: book.description?.trimmingCharacters(in: .whitespacesAndNewlines),
            genres: book.tags(in: "Genre"),
            moods: book.tags(in: "Mood"),
            contentWarnings: book.tags(in: "Content Warning"),
            releaseDate: book.releaseDate.flatMap(releaseDate(from:))
        )
    }

    /// Hardcover's "YYYY-MM-DD", read as a UTC calendar day so it is the same day everywhere.
    static func releaseDate(from text: String) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Every volume of a series, in reading order — including the ones the reader does not own,
    /// which is the whole point: a series card can only say what is missing if it knows the
    /// full list.
    static func seriesVolumes(seriesID: Int, token: String) async throws -> [SeriesVolume] {
        let document = seriesVolumesQuery
        let response = try await execute(
            query: document,
            variables: ["id": seriesID],
            token: token,
            as: SeriesVolumesResponse.self
        )
        return (response.series.first?.bookSeries ?? []).map {
            SeriesVolume(
                bookID: $0.book.id,
                title: $0.book.title,
                position: $0.position,
                artworkURL: $0.book.image?.url.flatMap(URL.init(string:))
            )
        }
    }

    static func removeFromShelf(userBookID: Int, token: String) async throws {
        let document = deleteUserBookMutation
        _ = try await execute(
            query: document,
            variables: ["id": userBookID],
            token: token,
            as: DeleteUserBookResponse.self
        )
    }
}

extension HardcoverLink {
    /// Lives here rather than beside `HardcoverLink`, which the widget target also builds and
    /// which must not drag the networking layer in with it.
    init(_ hit: HardcoverAPI.SearchHit, status: Status = .local) {
        self.init(
            id: hit.id,
            title: hit.title,
            author: hit.author,
            artworkURL: hit.artworkURL,
            status: status
        )
    }
}
