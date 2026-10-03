import Foundation

// The wire format between the iPhone and the Apple Watch. Pure Foundation on purpose: this
// file is compiled into both targets, so nothing here may import SwiftData, UIKit or WatchKit.

/// Everything the watch needs to draw its library, pushed through `updateApplicationContext`.
struct LibrarySnapshot: Codable, Sendable, Equatable {
    let books: [BookSummary]
    let nowPlaying: NowPlayingState?
    /// The phone's skip settings, so the watch's buttons match. Optional: an older phone
    /// build sends neither, and the watch keeps its 15 s default.
    let skipBackSeconds: TimeInterval?
    let skipForwardSeconds: TimeInterval?
    let sentAt: Date

    init(
        books: [BookSummary],
        nowPlaying: NowPlayingState? = nil,
        skipBackSeconds: TimeInterval? = nil,
        skipForwardSeconds: TimeInterval? = nil,
        sentAt: Date = Date()
    ) {
        self.books = books
        self.nowPlaying = nowPlaying
        self.skipBackSeconds = skipBackSeconds
        self.skipForwardSeconds = skipForwardSeconds
        self.sentAt = sentAt
    }
}

/// One book, flattened out of `AudiobookModel` and its relationships.
struct BookSummary: Codable, Sendable, Equatable {
    let id: UUID
    let title: String
    let author: String?
    let duration: TimeInterval
    let currentPosition: TimeInterval
    /// When `currentPosition` was written. Drives last-write-wins; nil means "older than anything".
    let positionUpdatedAt: Date?
    let playbackSpeed: Double?
    let isFinished: Bool
    let chapters: [ChapterSummary]
    let bookmarks: [BookmarkSummary]
    /// The AudiobookShelf item the book is linked to, so the watch can stream it. Optional: an
    /// older phone build sends none.
    let serverItemID: String?

    init(
        id: UUID,
        title: String,
        author: String? = nil,
        duration: TimeInterval,
        currentPosition: TimeInterval,
        positionUpdatedAt: Date? = nil,
        playbackSpeed: Double? = nil,
        isFinished: Bool = false,
        chapters: [ChapterSummary] = [],
        bookmarks: [BookmarkSummary] = [],
        serverItemID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.duration = duration
        self.currentPosition = currentPosition
        self.positionUpdatedAt = positionUpdatedAt
        self.playbackSpeed = playbackSpeed
        self.isFinished = isFinished
        self.chapters = chapters
        self.bookmarks = bookmarks
        self.serverItemID = serverItemID
    }
}

/// A chapter's place on the book timeline. `number` is the identity used by every request,
/// transfer and eviction, so it matches `ChapterModel.chapterNumber`.
struct ChapterSummary: Codable, Sendable, Equatable {
    let number: Int
    let title: String?
    let start: TimeInterval
    let end: TimeInterval

    init(number: Int, title: String? = nil, start: TimeInterval, end: TimeInterval) {
        self.number = number
        self.title = title
        self.start = start
        self.end = end
    }
}

struct BookmarkSummary: Codable, Sendable, Equatable {
    let id: UUID
    let timestamp: TimeInterval
    let title: String?
    let dateCreated: Date?

    init(id: UUID = UUID(), timestamp: TimeInterval, title: String? = nil, dateCreated: Date? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.title = title
        self.dateCreated = dateCreated
    }
}

/// What the *other* side is playing right now, so a screen can mirror it.
struct NowPlayingState: Codable, Sendable, Equatable {
    let bookID: UUID
    let position: TimeInterval
    let rate: Float
    let isPlaying: Bool

    init(bookID: UUID, position: TimeInterval, rate: Float, isPlaying: Bool) {
        self.bookID = bookID
        self.position = position
        self.rate = rate
        self.isPlaying = isPlaying
    }
}

/// One-shot facts, sent through `transferUserInfo` so they are queued and guaranteed.
enum SyncEvent: Codable, Sendable, Equatable {
    case progress(bookID: UUID, position: TimeInterval, at: Date)
    /// Wall-clock seconds the watch played `bookID`, ending at `at`. The phone keeps the log.
    case listened(bookID: UUID, seconds: TimeInterval, at: Date)
    case bookmarkAdded(bookID: UUID, bookmark: BookmarkSummary)
    case chapterRequested(bookID: UUID, chapterNumber: Int)
    case chapterDeleted(bookID: UUID, chapterNumber: Int)
    case bookCleared(bookID: UUID)
    /// What the watch actually holds, so the phone can reconcile its transfer queue.
    case watchInventory(bookID: UUID, chapterNumbers: [Int])
    /// Only the sender sees `WCSessionFileTransfer.progress`, so it forwards the fraction.
    case transferProgress(bookID: UUID, chapterNumber: Int, fraction: Double)
    /// Playback started here: stop making noise over there.
    case pauseOtherSide
    /// The phone's AudiobookShelf sign-in, so the watch can stream on its own. Nil: signed out.
    case serverAccount(ServerAccount?)
    /// The watch streamed `itemID` as a book it created under `bookID`: it joins the Library.
    case joined(bookID: UUID, itemID: String)
}

/// What the watch needs to talk to AudiobookShelf by itself. Sent through `transferUserInfo`,
/// which WatchConnectivity encrypts; the watch keeps the token in its own keychain.
struct ServerAccount: Codable, Sendable, Equatable {
    let server: URL
    let token: String
    /// The server library the phone has selected, the one the watch browses.
    let library: String?
}

/// Transport control of the other side, sent through `sendMessage` while reachable.
enum RemoteCommand: Codable, Sendable, Equatable {
    case play(bookID: UUID)
    case toggle
    case pause
    case skipForward(TimeInterval)
    case skipBackward(TimeInterval)
    case seek(TimeInterval)
    case setRate(Float)
    case playChapter(bookID: UUID, chapterNumber: Int)
}

enum TransferKind: String, Codable, Sendable {
    case cover
    case chapter
}

/// Rides along with `transferFile(_:metadata:)`, which takes a property-list dictionary.
/// Rather than flatten the fields into plist types, the whole thing goes as JSON `Data`
/// under one key — one encoder, one decoder, nothing to keep in step.
struct TransferMetadata: Codable, Sendable, Equatable {
    let kind: TransferKind
    let bookID: UUID
    let chapterNumber: Int?
    let duration: TimeInterval?
    let byteCount: Int?

    init(
        kind: TransferKind,
        bookID: UUID,
        chapterNumber: Int? = nil,
        duration: TimeInterval? = nil,
        byteCount: Int? = nil
    ) {
        self.kind = kind
        self.bookID = bookID
        self.chapterNumber = chapterNumber
        self.duration = duration
        self.byteCount = byteCount
    }

    var dictionary: [String: Any] {
        guard let data = try? SyncCodec.encode(self) else { return [:] }
        return [SyncKeys.metadata: data]
    }

    init?(dictionary: [String: Any]) {
        guard let data = dictionary[SyncKeys.metadata] as? Data,
              let decoded = try? SyncCodec.decode(TransferMetadata.self, from: data) else {
            return nil
        }
        self = decoded
    }
}

/// The single dictionary key each payload travels under.
enum SyncKeys {
    static let snapshot = "snapshot"
    static let event = "event"
    static let command = "command"
    static let metadata = "meta"
}

/// One JSON configuration for both sides. ISO-8601 dates so a strategy mismatch cannot
/// silently shift `positionUpdatedAt` and break last-write-wins.
enum SyncCodec {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}
