import Foundation

/// Browsing a library the way its shelves are organised: series, authors, search.
extension AudiobookShelfAPI {
    static let seriesPageSize = 30

    /// One page of series by name, each with its books, plus the total number of series.
    static func series(
        server: URL,
        token: String,
        library: String,
        page: Int
    ) async throws -> (items: [Series], total: Int) {
        struct Response: Decodable {
            let results: [Series]
            let total: Int
        }
        let url = server.appending(path: "api/libraries/\(library)/series").appending(queryItems: [
            URLQueryItem(name: "limit", value: String(seriesPageSize)),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "sort", value: "name")
        ])
        let response = try await send(authorized(url, token: token), as: Response.self)
        return (response.results, response.total)
    }

    /// The query for a library's items in one series.
    ///
    /// Built by hand: the filter value is `series.<base64 id>`, and `URLQueryItem` leaves the
    /// `+` and `/` of base64 alone. The server reads a `+` in a query as a space, which breaks
    /// the id and silently matches nothing.
    static func seriesItemsURL(server: URL, library: String, series: String) -> URL? {
        let encoded = Data(series.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "%2B")
            .replacingOccurrences(of: "/", with: "%2F")
            .replacingOccurrences(of: "=", with: "%3D")
        var components = URLComponents(
            url: server.appending(path: "api/libraries/\(library)/items"),
            resolvingAgainstBaseURL: false
        )
        components?.percentEncodedQuery = "filter=series.\(encoded)&minified=1&limit=500"
        return components?.url
    }

    /// A series' books in series order.
    static func seriesItems(server: URL, token: String, library: String, series: String) async throws -> [Item] {
        struct Response: Decodable { let results: [Item] }
        guard let url = seriesItemsURL(server: server, library: library, series: series) else {
            throw Failure.invalidServer
        }
        return try await send(authorized(url, token: token), as: Response.self).results.sorted(by: Item.bySequence)
    }

    /// Every author of a library, by name. Not paged by the server; one author row is small.
    static func authors(server: URL, token: String, library: String) async throws -> [Author] {
        struct Response: Decodable { let authors: [Author] }
        let url = server.appending(path: "api/libraries/\(library)/authors")
        return try await send(authorized(url, token: token), as: Response.self).authors
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// An author's books in one library, by title.
    ///
    /// Through the author rather than `filter=authors.<id>`: AudiobookShelf can leave the
    /// filter table pointing at a stale author id after a merge, and the filter then finds one
    /// book instead of all of them. The author record is what the web client reads.
    static func authorItems(server: URL, token: String, library: String, author: String) async throws -> [Item] {
        struct Response: Decodable { let libraryItems: [Item]? }
        let url = server.appending(path: "api/authors/\(author)").appending(queryItems: [
            URLQueryItem(name: "include", value: "items"),
            URLQueryItem(name: "library", value: library)
        ])
        return (try await send(authorized(url, token: token), as: Response.self).libraryItems ?? [])
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    static func search(server: URL, token: String, library: String, query: String) async throws -> SearchResults {
        struct Response: Decodable {
            struct BookHit: Decodable { let libraryItem: Item }
            struct SeriesHit: Decodable {
                let series: Series
                let books: [Item]?
            }
            let book: [BookHit]?
            let series: [SeriesHit]?
            let authors: [Author]?
        }
        let url = server.appending(path: "api/libraries/\(library)/search")
            .appending(queryItems: [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "25")])
        let response = try await send(authorized(url, token: token), as: Response.self)
        return SearchResults(
            books: (response.book ?? []).map(\.libraryItem),
            series: (response.series ?? []).map { hit in
                var series = hit.series
                series.books = hit.books
                return series
            },
            authors: response.authors ?? []
        )
    }

    static func authorImageRequest(server: URL, token: String, author: String, width: Int = 200) -> URLRequest {
        authorized(
            server.appending(path: "api/authors/\(author)/image")
                .appending(queryItems: [URLQueryItem(name: "width", value: String(width))]),
            token: token
        )
    }
}
