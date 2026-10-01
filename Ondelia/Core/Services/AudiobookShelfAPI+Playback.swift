import Foundation

/// Streaming a book and keeping its listening position in step with the server.
extension AudiobookShelfAPI {
    /// What playing an item needs: its audio files on the book's timeline, its chapters, and
    /// enough metadata to give it a library entry.
    struct PlaybackItem: Decodable {
        struct Media: Decodable {
            struct Track: Decodable {
                let startOffset: Double
                let duration: Double
                /// A server path, "/api/items/<id>/file/<ino>".
                let contentUrl: String
            }
            struct Chapter: Decodable {
                let start: Double
                let end: Double
                let title: String?
            }
            struct Metadata: Decodable {
                struct Author: Decodable { let name: String }
                let title: String?
                let authors: [Author]?
                let narrators: [String]?
            }
            let duration: Double?
            let tracks: [Track]?
            let chapters: [Chapter]?
            let metadata: Metadata
        }
        let id: String
        let media: Media

        var author: String? {
            let names = media.metadata.authors?.map(\.name).joined(separator: ", ")
            return names?.isEmpty == false ? names : nil
        }

        var narrator: String? {
            let names = media.metadata.narrators?.joined(separator: ", ")
            return names?.isEmpty == false ? names : nil
        }
    }

    /// The server's record of how far into an item the user is.
    struct MediaProgress: Decodable, Equatable {
        let currentTime: Double
        let isFinished: Bool
        /// Milliseconds since 1970, on the server's clock.
        let lastUpdate: Double

        var updatedAt: Date { Date(timeIntervalSince1970: lastUpdate / 1000) }
    }

    static func playbackItem(server: URL, token: String, item: String) async throws -> PlaybackItem {
        let url = server.appending(path: "api/items/\(item)")
            .appending(queryItems: [URLQueryItem(name: "expanded", value: "1")])
        return try await send(authorized(url, token: token), as: PlaybackItem.self)
    }

    /// A track's streaming address. The server path is joined under the server's own path, so
    /// a server behind a reverse proxy at "/abs" still resolves.
    static func streamURL(server: URL, contentPath: String) -> URL {
        server.appending(path: contentPath.hasPrefix("/") ? String(contentPath.dropFirst()) : contentPath)
    }

    /// Nil when the user has never played the item.
    static func progress(
        server: URL,
        token: String,
        item: String,
        timeout: TimeInterval = 20
    ) async throws -> MediaProgress? {
        var request = authorized(server.appending(path: "api/me/progress/\(item)"), token: token)
        request.timeoutInterval = timeout
        do {
            return try await send(request, as: MediaProgress.self)
        } catch Failure.http(404) {
            return nil
        }
    }

    static func updateProgress(
        server: URL,
        token: String,
        item: String,
        currentTime: Double,
        duration: Double,
        isFinished: Bool
    ) async throws {
        var request = authorized(server.appending(path: "api/me/progress/\(item)"), token: token)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let fraction = duration > 0 ? min(max(currentTime / duration, 0), 1) : 0
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "currentTime": currentTime,
            "duration": duration,
            "progress": isFinished ? 1 : fraction,
            "isFinished": isFinished
        ])
        let (_, response) = try await URLSession.shared.data(for: request)
        try check(response)
    }
}
