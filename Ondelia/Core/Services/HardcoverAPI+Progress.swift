import Foundation

// MARK: - Reading progress
//
// Hardcover keeps a listener's position on a `user_book_reads` row: one row per pass through a
// book, holding how far in the reader is and which edition that measurement refers to. Seconds
// only mean anything against an audiobook edition — Hardcover divides `progress_seconds` by that
// edition's `audio_seconds` to get the percentage — so the edition has to be found first.
extension HardcoverAPI {
    /// One audiobook edition of a book, with the length Hardcover measures progress against.
    struct AudioEdition: Decodable, Hashable, Sendable {
        let id: Int
        let audioSeconds: Int

        enum CodingKeys: String, CodingKey {
            case id
            case audioSeconds = "audio_seconds"
        }
    }

    /// The audiobook edition of `bookID` whose length best matches the file in the library.
    ///
    /// A book can carry a dozen audio editions — abridged, a second narrator, another language —
    /// and each has its own length, so the wrong one skews every percentage that follows.
    /// Duration is the one property the local file and the edition can be compared on.
    static func audiobookEdition(
        bookID: Int,
        matching duration: TimeInterval,
        token: String
    ) async throws -> AudioEdition? {
        let document = """
            query AudiobookEditions($id: Int!) {
              editions(
                where: {book_id: {_eq: $id}, audio_seconds: {_is_null: false}}
                order_by: {users_count: desc}
                limit: 20
              ) {
                id
                audio_seconds
              }
            }
            """
        let response = try await execute(
            query: document,
            variables: ["id": bookID],
            token: token,
            as: EditionsResponse.self
        )
        return closestEdition(response.editions, to: duration)
    }

    /// Picks the edition closest in length to `duration`, or the most popular one when the
    /// local file has no duration to compare. Editions arrive most-listened first, so a tie
    /// between two equally close editions goes to the one more readers own.
    static func closestEdition(_ editions: [AudioEdition], to duration: TimeInterval) -> AudioEdition? {
        let usable = editions.filter { $0.audioSeconds > 0 }
        guard duration > 0 else { return usable.first }
        return usable.min {
            abs(Double($0.audioSeconds) - duration) < abs(Double($1.audioSeconds) - duration)
        }
    }

    /// Opens a read on a shelf row, returning the id needed to move it later.
    static func startRead(
        userBookID: Int,
        editionID: Int?,
        seconds: Int,
        startedAt: String,
        finishedAt: String?,
        token: String
    ) async throws -> Int {
        let document = """
            mutation InsertUserBookRead($user_book_id: Int!, $read: DatesReadInput!) {
              insert_user_book_read(user_book_id: $user_book_id, user_book_read: $read) {
                id
                error
              }
            }
            """
        let response = try await execute(
            query: document,
            variables: [
                "user_book_id": userBookID,
                "read": readInput(
                    editionID: editionID,
                    seconds: seconds,
                    startedAt: startedAt,
                    finishedAt: finishedAt
                )
            ],
            token: token,
            as: InsertUserBookReadResponse.self
        )
        // This mutation reports its failures in an `error` field rather than as a GraphQL error,
        // so a bad edition id comes back as a perfectly successful response saying no.
        if let message = response.insertUserBookRead?.error { throw Failure.graphQL(message) }
        guard let id = response.insertUserBookRead?.id else { throw Failure.noData }
        return id
    }

    /// Moves an open read to a new position, and closes it when `finishedAt` is given.
    static func updateRead(
        id: Int,
        editionID: Int?,
        seconds: Int,
        finishedAt: String?,
        token: String
    ) async throws {
        let document = """
            mutation UpdateUserBookRead($id: Int!, $read: DatesReadInput!) {
              update_user_book_read(id: $id, object: $read) {
                id
                error
              }
            }
            """
        let response = try await execute(
            query: document,
            variables: [
                "id": id,
                "read": readInput(
                    editionID: editionID,
                    seconds: seconds,
                    startedAt: nil,
                    finishedAt: finishedAt
                )
            ],
            token: token,
            as: UpdateUserBookReadResponse.self
        )
        if let message = response.updateUserBookRead?.error { throw Failure.graphQL(message) }
    }

    /// `DatesReadInput`, with the keys that have no value left out: sending `edition_id: null`
    /// would clear the edition an earlier push established.
    private static func readInput(
        editionID: Int?,
        seconds: Int,
        startedAt: String?,
        finishedAt: String?
    ) -> [String: Any] {
        var input: [String: Any] = ["progress_seconds": seconds]
        if let editionID { input["edition_id"] = editionID }
        if let startedAt { input["started_at"] = startedAt }
        if let finishedAt { input["finished_at"] = finishedAt }
        return input
    }

    /// Hardcover's `date` scalar: a plain calendar day, in the reader's own time zone, because
    /// that is the day they will expect to see on their profile.
    static func dateStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Responses

    struct EditionsResponse: Decodable {
        let editions: [AudioEdition]
    }

    struct InsertUserBookReadResponse: Decodable {
        let insertUserBookRead: ReadRow?

        enum CodingKeys: String, CodingKey {
            case insertUserBookRead = "insert_user_book_read"
        }
    }

    struct UpdateUserBookReadResponse: Decodable {
        let updateUserBookRead: ReadRow?

        enum CodingKeys: String, CodingKey {
            case updateUserBookRead = "update_user_book_read"
        }
    }

    struct ReadRow: Decodable {
        let id: Int?
        let error: String?
    }
}
