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
        let document = """
            query GetBooks($query: String!, $per_page: Int!) {
              search(query: $query, query_type: "book", per_page: $per_page, page: 1) {
                results
              }
            }
            """
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
        let document = """
            mutation InsertUserBook($book_id: Int!, $status_id: Int!) {
              insert_user_book(object: {book_id: $book_id, status_id: $status_id}) {
                id
              }
            }
            """
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
        let document = """
            query BookSeries($id: Int!) {
              books(where: {id: {_eq: $id}}, limit: 1) {
                book_series {
                  position
                  series {
                    id
                    name
                  }
                }
              }
            }
            """
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
        let document = """
            query BookDetails($id: Int!) {
              books(where: {id: {_eq: $id}}, limit: 1) {
                description
                cached_tags
              }
            }
            """
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
            contentWarnings: book.tags(in: "Content Warning")
        )
    }

    /// Every volume of a series, in reading order — including the ones the reader does not own,
    /// which is the whole point: a series card can only say what is missing if it knows the
    /// full list.
    static func seriesVolumes(seriesID: Int, token: String) async throws -> [SeriesVolume] {
        let document = """
            query SeriesBooks($id: Int!) {
              series(where: {id: {_eq: $id}}, limit: 1) {
                book_series(
                  distinct_on: position
                  order_by: [{position: asc}, {book: {users_count: desc}}]
                  where: {
                    compilation: {_eq: false}
                    book: {canonical_id: {_is_null: true}, is_partial_book: {_eq: false}}
                  }
                ) {
                  position
                  book {
                    id
                    title
                  }
                }
              }
            }
            """
        let response = try await execute(
            query: document,
            variables: ["id": seriesID],
            token: token,
            as: SeriesVolumesResponse.self
        )
        return (response.series.first?.bookSeries ?? []).map {
            SeriesVolume(bookID: $0.book.id, title: $0.book.title, position: $0.position)
        }
    }

    static func removeFromShelf(userBookID: Int, token: String) async throws {
        let document = """
            mutation DeleteUserBook($id: Int!) {
              delete_user_book(id: $id) {
                book_id
              }
            }
            """
        _ = try await execute(
            query: document,
            variables: ["id": userBookID],
            token: token,
            as: DeleteUserBookResponse.self
        )
    }
}

// MARK: - Responses

extension HardcoverAPI {
    /// One book from search. `search.results` is a raw Typesense payload, hence the nesting.
    struct SearchHit: Decodable, Identifiable, Hashable {
        let id: Int
        let title: String
        let authorNames: [String]
        let image: Artwork?

        var author: String { authorNames.first ?? "" }
        var artworkURL: URL? { image?.url.flatMap(URL.init(string:)) }

        struct Artwork: Decodable, Hashable {
            let url: String?
        }

        enum CodingKeys: String, CodingKey {
            case id, title, image
            case authorNames = "author_names"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Typesense returns the id as a string on some indexes and a number on others.
            if let text = try? container.decode(String.self, forKey: .id) {
                guard let value = Int(text) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .id, in: container, debugDescription: "Invalid id string: \(text)"
                    )
                }
                id = value
            } else {
                id = try container.decode(Int.self, forKey: .id)
            }
            title = try container.decode(String.self, forKey: .title)
            authorNames = (try? container.decode([String].self, forKey: .authorNames)) ?? []
            image = try container.decodeIfPresent(Artwork.self, forKey: .image)
        }
    }

    struct SearchResponse: Decodable {
        let search: Results

        struct Results: Decodable {
            let results: Hits

            struct Hits: Decodable {
                let hits: [Hit]

                struct Hit: Decodable {
                    let document: SearchHit
                }
            }
        }
    }

    /// The blurb and the reader-applied tags for one book.
    struct BookDetails: Hashable, Sendable {
        let summary: String?
        let genres: [String]
        let moods: [String]
        let contentWarnings: [String]
    }

    struct BookDetailsResponse: Decodable {
        let books: [Book]

        struct Book: Decodable {
            let description: String?
            /// `cached_tags` is a free-form jsonb column: a bucket per category, each holding
            /// rows that carry a `tag` among other fields. Anything that does not fit that
            /// shape is dropped rather than failing the whole decode.
            let cachedTags: [String: [Tag]]

            struct Tag: Decodable {
                let tag: String
            }

            func tags(in category: String) -> [String] {
                (cachedTags[category] ?? []).map(\.tag)
            }

            enum CodingKeys: String, CodingKey {
                case description
                case cachedTags = "cached_tags"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                description = try? container.decodeIfPresent(String.self, forKey: .description)
                cachedTags = (try? container.decodeIfPresent([String: [Tag]].self, forKey: .cachedTags)) ?? [:]
            }
        }
    }

    /// Where one book sits in one series.
    struct SeriesRef: Hashable, Sendable {
        let id: Int
        let name: String
        let position: Double?
    }

    struct SeriesVolumesResponse: Decodable {
        let series: [Entry]

        struct Entry: Decodable {
            let bookSeries: [Volume]

            enum CodingKeys: String, CodingKey {
                case bookSeries = "book_series"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                bookSeries = (try? container.decode([Volume].self, forKey: .bookSeries)) ?? []
            }
        }

        struct Volume: Decodable {
            let position: Double?
            let book: Book

            struct Book: Decodable {
                let id: Int
                let title: String
            }

            enum CodingKeys: String, CodingKey {
                case position, book
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                book = try container.decode(Book.self, forKey: .book)
                position = try container.decodeSeriesPosition(forKey: .position)
            }
        }
    }

    struct BookSeriesResponse: Decodable {
        let books: [Book]

        struct Book: Decodable {
            let bookSeries: [Entry]

            enum CodingKeys: String, CodingKey {
                case bookSeries = "book_series"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                bookSeries = (try? container.decode([Entry].self, forKey: .bookSeries)) ?? []
            }
        }

        struct Entry: Decodable {
            /// Hardcover stores the position as a number on some rows and a string on others.
            let position: Double?
            let series: Series

            struct Series: Decodable {
                let id: Int
                let name: String
            }

            enum CodingKeys: String, CodingKey {
                case position, series
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                series = try container.decode(Series.self, forKey: .series)
                position = try container.decodeSeriesPosition(forKey: .position)
            }
        }
    }

    struct InsertUserBookResponse: Decodable {
        let insertUserBook: Row

        struct Row: Decodable {
            let id: Int
        }

        enum CodingKeys: String, CodingKey {
            case insertUserBook = "insert_user_book"
        }
    }

    struct DeleteUserBookResponse: Decodable {
        let deleteUserBook: Row?

        struct Row: Decodable {
            let bookID: Int

            enum CodingKeys: String, CodingKey {
                case bookID = "book_id"
            }
        }

        enum CodingKeys: String, CodingKey {
            case deleteUserBook = "delete_user_book"
        }
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

// MARK: - Shared decoding

private extension KeyedDecodingContainer {
    /// Hardcover writes the series position as a number on some rows and a string on others,
    /// and omits it for a volume whose place is unrecorded.
    func decodeSeriesPosition(forKey key: Key) throws -> Double? {
        if let number = try? decodeIfPresent(Double.self, forKey: key) { return number }
        guard let text = try? decodeIfPresent(String.self, forKey: key) else { return nil }
        return Double(text)
    }
}
