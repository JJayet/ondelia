import Foundation

/// The slice of the AudiobookShelf REST API this app speaks: sign in, list book libraries,
/// page their items, and download one to import. Series, authors and search are in
/// `+Browse`, the decoded types in `+Models`.
///
/// Every call takes the server and token explicitly, so this stays a set of pure requests and
/// `AudiobookShelfService` owns what is stored.
enum AudiobookShelfAPI {
    enum Failure: LocalizedError {
        case invalidServer
        /// The login itself was refused. Any later 401 is a token the server no longer takes.
        case badCredentials
        case http(Int)
        case unexpectedResponse

        var errorDescription: String? {
            switch self {
            case .invalidServer:
                return NSLocalizedString(
                    "That server address is not valid.",
                    comment: "AudiobookShelf: malformed server URL"
                )
            case .badCredentials:
                return NSLocalizedString(
                    "AudiobookShelf rejected the sign-in. Check your username and password.",
                    comment: "AudiobookShelf authentication failure"
                )
            case .http(401), .http(403):
                return NSLocalizedString(
                    "The server no longer accepts this sign-in. Sign out and sign in again in Settings.",
                    comment: "AudiobookShelf: saved token refused"
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

    static let pageSize = 50

    /// What the reader typed, as a base URL: trimmed, `https://` when no scheme was given, no
    /// trailing slash. A path is kept, for servers behind a reverse proxy at `/audiobookshelf`.
    /// `port`, from the Port field, replaces any port typed in the address; out of range, the
    /// address is rejected.
    static func serverURL(from input: String, port: Int? = nil) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard var parts = URLComponents(string: text), let scheme = parts.scheme?.lowercased(),
              scheme == "http" || scheme == "https", parts.host?.isEmpty == false
        else { return nil }
        if let port {
            guard (1...65535).contains(port) else { return nil }
            parts.port = port
        }
        return parts.url
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
        do {
            return try await send(request, as: Response.self).user.token
        } catch Failure.http(401) {
            throw Failure.badCredentials
        }
    }

    /// Book libraries only: podcast libraries hold episodes, which this app does not import.
    static func libraries(server: URL, token: String) async throws -> [Library] {
        struct Response: Decodable { let libraries: [Library] }
        let request = authorized(server.appending(path: "api/libraries"), token: token)
        return try await send(request, as: Response.self).libraries.filter { $0.mediaType == "book" }
    }

    /// `collapseSeries` folds each series into one entry, carrying `collapsedSeries`, the way
    /// the AudiobookShelf web client shows a big library.
    static func itemsURL(
        server: URL,
        library: String,
        page: Int,
        collapseSeries: Bool = false,
        limit: Int = pageSize
    ) -> URL {
        var query = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "sort", value: "media.metadata.title"),
            URLQueryItem(name: "minified", value: "1")
        ]
        if collapseSeries { query.append(URLQueryItem(name: "collapseseries", value: "1")) }
        return server.appending(path: "api/libraries/\(library)/items").appending(queryItems: query)
    }

    /// One page of a library, sorted by title, plus the total number of entries.
    static func items(
        server: URL,
        token: String,
        library: String,
        page: Int,
        collapseSeries: Bool = false,
        limit: Int = pageSize
    ) async throws -> (items: [Item], total: Int) {
        struct Response: Decodable {
            let results: [Item]
            let total: Int
        }
        let url = itemsURL(server: server, library: library, page: page, collapseSeries: collapseSeries, limit: limit)
        let response = try await send(authorized(url, token: token), as: Response.self)
        return (response.results, response.total)
    }

    /// Every book of a library, series unfolded, fetched a few hundred at a time.
    static func allItems(server: URL, token: String, library: String) async throws -> [Item] {
        var all: [Item] = []
        var page = 0
        while true {
            let (items, total) = try await self.items(server: server, token: token, library: library, page: page, limit: 500)
            all += items
            guard !items.isEmpty, all.count < total else { return all }
            page += 1
        }
    }

    static func coverRequest(server: URL, token: String, item: String, width: Int = 300) -> URLRequest {
        authorized(
            server.appending(path: "api/items/\(item)/cover")
                .appending(queryItems: [URLQueryItem(name: "width", value: String(width))]),
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

    static func authorized(_ url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        // Header, not `?token=`: a token in the URL ends up in proxy and server access logs.
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        return request
    }

    static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw Failure.unexpectedResponse }
        guard (200...299).contains(http.statusCode) else { throw Failure.http(http.statusCode) }
    }

    static func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw Failure.unexpectedResponse
        }
    }
}
