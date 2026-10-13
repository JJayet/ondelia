import Foundation

/// Listening time, as the server's statistics count it. The position alone (`updateProgress`)
/// leaves them at zero: they add up playback sessions. The app records its own, so they go up
/// the way the official app sends offline ones — keyed by id, so a session sent again after it
/// grew is updated rather than counted twice.
extension AudiobookShelfAPI {
    struct LocalSession: Encodable, Equatable {
        let id: String
        let libraryItemId: String
        var mediaType = "book"
        let displayTitle: String
        let displayAuthor: String?
        let duration: Double
        /// Local, in the server's numbering of play methods.
        var playMethod = 3
        var mediaPlayer = "Ondelia"
        /// The listener's day. The server only derives it, from its own clock, when this is missing.
        let date: String
        let dayOfWeek: String
        let timeListening: Double
        let startTime: Double
        /// The server takes it as the item's position when the session is newer than the
        /// position it holds.
        let currentTime: Double
        /// Milliseconds since 1970.
        let startedAt: Double
        let updatedAt: Double

        init(
            _ session: ListeningSessionModel,
            item: String,
            position: Double,
            duration: Double,
            timeZone: TimeZone = .current
        ) {
            id = session.id.uuidString.lowercased()
            libraryItemId = item
            displayTitle = session.title
            displayAuthor = session.author
            self.duration = duration
            let ended = session.startedAt.addingTimeInterval(session.seconds)
            // English names and a fixed format: the server stores what the web client parses.
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            date = formatter.string(from: session.startedAt)
            formatter.dateFormat = "EEEE"
            dayOfWeek = formatter.string(from: session.startedAt)
            timeListening = session.seconds
            startTime = position
            currentTime = position
            startedAt = (session.startedAt.timeIntervalSince1970 * 1000).rounded()
            updatedAt = (ended.timeIntervalSince1970 * 1000).rounded()
        }
    }

    struct LocalSessionResult: Decodable {
        let id: String
        let success: Bool
        /// Whether the server took the session's position as the item's.
        let progressSynced: Bool?
    }

    /// The server's verdict on each session; one it could not place fails alone.
    static func syncLocalSessions(
        server: URL,
        token: String,
        sessions: [LocalSession]
    ) async throws -> [LocalSessionResult] {
        struct Body: Encodable { let sessions: [LocalSession] }
        struct Response: Decodable { let results: [LocalSessionResult] }
        var request = authorized(server.appending(path: "api/session/local-all"), token: token)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(sessions: sessions))
        return try await send(request, as: Response.self).results
    }
}
