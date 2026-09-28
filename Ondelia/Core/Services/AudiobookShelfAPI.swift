import Foundation

/// The slice of the AudiobookShelf REST API this app speaks: sign in, list book libraries,
/// page or search their items, and download one to import.
///
/// Every call takes the server and token explicitly, so this stays a set of pure requests and
/// `AudiobookShelfService` owns what is stored.
enum AudiobookShelfAPI {
    enum Failure: LocalizedError {
        case invalidServer
        case http(Int)
        case unexpectedResponse

        var errorDescription: String? {
            switch self {
            case .invalidServer:
                return NSLocalizedString(
                    "That server address is not valid.",
                    comment: "AudiobookShelf: malformed server URL"
                )
            case .http(401), .http(403):
                return NSLocalizedString(
                    "AudiobookShelf rejected the sign-in. Check your username and password.",
                    comment: "AudiobookShelf authentication failure"
                )
            case .http(let code):
                return String(
                    format: NSLocalizedString(
                        "AudiobookShelf returned an error (%d).",
                        comment: "AudiobookShelf HTTP failure, %d is the status code"
                    ),
                    code
                )
            case .unexpectedResponse:
                return NSLocalizedString(
                    "The server did not answer like an AudiobookShelf server.",
                    comment: "AudiobookShelf undecodable response"
                )
            }
        }
    }

    struct Library: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
        let mediaType: String
    }

    struct Item: Decodable, Identifiable, Hashable {
        struct Media: Decodable, Hashable {
            struct Metadata: Decodable, Hashable {
                struct Author: Decodable, Hashable { let name: String }
                let title: String?
                /// Filled by the minified item list.
                let authorName: String?
                /// Filled by search, which returns expanded items instead.
                let authors: [Author]?
            }
            let metadata: Metadata
            let duration: Double?
        }
        let id: String
        let media: Media

        var title: String { media.metadata.title ?? "" }

        var author: String? {
            if let name = media.metadata.authorName, !name.isEmpty { return name }
            let names = media.metadata.authors?.map(\.name).joined(separator: ", ")
            return names?.isEmpty == false ? names : nil
        }
    }

    static let pageSize = 50

    /// What the reader typed, as a base URL: trimmed, `https://` when no scheme was given, no
    /// trailing slash. A path is kept, for servers behind a reverse proxy at `/audiobookshelf`.
    static func serverURL(from input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host?.isEmpty == false
        else { return nil }
        return url
    }

    /// Signs in with a username and password and returns the user's API token.
    ///
    /// ponytail: uses the legacy non-expiring `user.token`, as BookPlayer does. When ABS drops
    /// it, switch to `accessToken` + `refreshToken` (sent with `x-return-tokens: true`).
    static func signIn(server: URL, username: String, password: String) async throws -> String {
        var request = URLRequest(url: server.appending(path: "login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["username": username, "password": password])

        struct Response: Decodable {
            struct User: Decodable { let token: String }
            let user: User
        }
        return try await send(request, as: Response.self).user.token
    }

    /// Book libraries only: podcast libraries hold episodes, which this app does not import.
    static func libraries(server: URL, token: String) async throws -> [Library] {
        struct Response: Decodable { let libraries: [Library] }
        let request = authorized(server.appending(path: "api/libraries"), token: token)
        return try await send(request, as: Response.self).libraries.filter { $0.mediaType == "book" }
    }

    static func itemsURL(server: URL, library: String, page: Int) -> URL {
        server.appending(path: "api/libraries/\(library)/items").appending(queryItems: [
            URLQueryItem(name: "limit", value: String(pageSize)),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "sort", value: "media.metadata.title"),
            URLQueryItem(name: "minified", value: "1")
        ])
    }

    /// One page of a library, sorted by title, plus the library's total item count.
    static func items(server: URL, token: String, library: String, page: Int) async throws -> (items: [Item], total: Int) {
        struct Response: Decodable {
            let results: [Item]
            let total: Int
        }
        let request = authorized(itemsURL(server: server, library: library, page: page), token: token)
        let response = try await send(request, as: Response.self)
        return (response.results, response.total)
    }

    static func search(server: URL, token: String, library: String, query: String) async throws -> [Item] {
        struct Response: Decodable {
            struct Hit: Decodable { let libraryItem: Item }
            let book: [Hit]
        }
        let url = server.appending(path: "api/libraries/\(library)/search")
            .appending(queryItems: [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "25")])
        return try await send(authorized(url, token: token), as: Response.self).book.map(\.libraryItem)
    }

    static func coverRequest(server: URL, token: String, item: String) -> URLRequest {
        authorized(
            server.appending(path: "api/items/\(item)/cover")
                .appending(queryItems: [URLQueryItem(name: "width", value: "120")]),
            token: token
        )
    }

    static func downloadRequest(server: URL, token: String, item: String) -> URLRequest {
        var request = authorized(server.appending(path: "api/items/\(item)/download"), token: token)
        // A big book streams for longer than any single-request timeout; the background session
        // still gives up after its own resource timeout.
        request.timeoutInterval = 60
        return request
    }

    /// Where finished downloads wait for their import. Application Support, not the temporary
    /// directory: the app can be killed between download and import, and the file must still
    /// be there at the next launch for `pendingDownloads` to find.
    static var pendingDownloadsFolder: URL {
        URL.applicationSupportDirectory.appending(path: "AudiobookShelfDownloads", directoryHint: .isDirectory)
    }

    /// Downloads a previous launch left unimported, with the item each came from.
    ///
    /// Laid out as `<item id>/<one folder per download>/<file>`, so the item id survives a
    /// relaunch. Empty folders — from an interrupted move, or an import that finished — are
    /// deleted on the way.
    static func pendingDownloads(in root: URL = pendingDownloadsFolder) -> [(item: String, file: URL)] {
        let fileManager = FileManager.default
        func contents(_ folder: URL) -> [URL] {
            (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        }
        return contents(root).flatMap { itemFolder in
            let downloads = contents(itemFolder).compactMap { download -> (item: String, file: URL)? in
                guard let file = contents(download).first else {
                    try? fileManager.removeItem(at: download)
                    return nil
                }
                return (itemFolder.lastPathComponent, file)
            }
            if downloads.isEmpty { try? fileManager.removeItem(at: itemFolder) }
            return downloads
        }
    }

    /// Moves a finished download of `item` into a fresh folder under `root` and returns
    /// the file. The download's own location is deleted as soon as its delegate call returns.
    ///
    /// The server answers with a zip of the item's folder, or with the audio file itself when
    /// the item is a single file. Both keep the server's filename, whose extension is what the
    /// import pipeline dispatches on.
    static func keepDownload(
        at location: URL,
        response: URLResponse?,
        item: String,
        in root: URL = pendingDownloadsFolder
    ) throws -> URL {
        guard let response else { throw Failure.unexpectedResponse }
        try check(response)

        var root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // A book can weigh gigabytes, and it is deleted once imported: not worth an iCloud backup.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)

        let folder = root.appending(path: safeFilename(item)).appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = response.suggestedFilename.map(safeFilename) ?? "\(safeFilename(item)).zip"
        let destination = folder.appending(path: name)
        try FileManager.default.moveItem(at: location, to: destination)
        return destination
    }

    /// A server-supplied name, reduced to a single path component.
    static func safeFilename(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty || cleaned.hasPrefix(".") ? "download\(cleaned)" : cleaned
    }

    // MARK: - Plumbing

    private static func authorized(_ url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        // Header, not `?token=`: a token in the URL ends up in proxy and server access logs.
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        return request
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw Failure.unexpectedResponse }
        guard (200...299).contains(http.statusCode) else { throw Failure.http(http.statusCode) }
    }

    private static func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw Failure.unexpectedResponse
        }
    }
}
