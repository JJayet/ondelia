import Foundation
import Testing
@testable import Isora

/// The watch and the phone never see each other's types, only these bytes, so the only thing
/// worth asserting is that every payload survives the round trip unchanged.
@Suite("Watch sync models")
struct SyncModelsTests {

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        try SyncCodec.decode(T.self, from: SyncCodec.encode(value))
    }

    @Test("A full library snapshot round-trips")
    func snapshotRoundTrip() throws {
        let bookID = UUID()
        let snapshot = LibrarySnapshot(
            books: [
                BookSummary(
                    id: bookID,
                    title: "Le Comte de Monte-Cristo",
                    author: "Alexandre Dumas",
                    duration: 3_600,
                    currentPosition: 42.5,
                    positionUpdatedAt: Date(timeIntervalSince1970: 1_757_000_000),
                    playbackSpeed: 1.25,
                    isFinished: false,
                    chapters: [
                        ChapterSummary(number: 1, title: "Marseille", start: 0, end: 1_200),
                        ChapterSummary(number: 2, title: nil, start: 1_200, end: 3_600)
                    ],
                    bookmarks: [
                        BookmarkSummary(
                            timestamp: 90,
                            title: "Le père",
                            dateCreated: Date(timeIntervalSince1970: 1_756_000_000)
                        )
                    ],
                    serverItemID: "li_abc123"
                )
            ],
            nowPlaying: NowPlayingState(bookID: bookID, position: 42.5, rate: 1.25, isPlaying: true),
            sentAt: Date(timeIntervalSince1970: 1_757_000_100)
        )

        #expect(try roundTrip(snapshot) == snapshot)
    }

    @Test("A snapshot with nothing playing round-trips")
    func emptySnapshotRoundTrip() throws {
        let snapshot = LibrarySnapshot(books: [], sentAt: Date(timeIntervalSince1970: 1))
        let decoded = try roundTrip(snapshot)
        #expect(decoded == snapshot)
        #expect(decoded.nowPlaying == nil)
    }

    @Test("Every sync event round-trips")
    func eventRoundTrip() throws {
        let bookID = UUID()
        let events: [SyncEvent] = [
            .progress(bookID: bookID, position: 12.5, at: Date(timeIntervalSince1970: 1_757_000_000)),
            .bookmarkAdded(bookID: bookID, bookmark: BookmarkSummary(timestamp: 7, title: "Ici")),
            .chapterRequested(bookID: bookID, chapterNumber: 3),
            .chapterDeleted(bookID: bookID, chapterNumber: 3),
            .bookCleared(bookID: bookID),
            .watchInventory(bookID: bookID, chapterNumbers: [3, 4, 5]),
            .transferProgress(bookID: bookID, chapterNumber: 4, fraction: 0.62),
            .pauseOtherSide,
            .serverAccount(ServerAccount(server: URL(string: "https://abs.example.com/abs")!, token: "t", library: "lib")),
            .serverAccount(nil),
            .joined(bookID: bookID, itemID: "li_abc123")
        ]

        for event in events {
            #expect(try roundTrip(event) == event)
        }
    }

    @Test("A book from a phone build without server links decodes with none")
    func summaryWithoutServerItem() throws {
        let json = #"{"id":"\#(UUID().uuidString)","title":"T","duration":1,"currentPosition":0,"#
            + #""isFinished":false,"chapters":[],"bookmarks":[]}"#
        let summary = try SyncCodec.decode(BookSummary.self, from: Data(json.utf8))
        #expect(summary.serverItemID == nil)
    }

    @Test("Watch events wait on their book; account and join events do not")
    func eventBookID() {
        let bookID = UUID()
        #expect(SyncEvent.listened(bookID: bookID, seconds: 30, at: Date()).bookID == bookID)
        #expect(SyncEvent.joined(bookID: bookID, itemID: "li").bookID == nil)
        #expect(SyncEvent.serverAccount(nil).bookID == nil)
    }

    @Test("Every remote command round-trips")
    func commandRoundTrip() throws {
        let commands: [RemoteCommand] = [
            .play(bookID: UUID()),
            .toggle,
            .pause,
            .skipForward(30),
            .skipBackward(15),
            .seek(1_234.5),
            .setRate(1.75),
            .playChapter(bookID: UUID(), chapterNumber: 12)
        ]

        for command in commands {
            #expect(try roundTrip(command) == command)
        }
    }

    @Test("Transfer metadata survives the WatchConnectivity dictionary")
    func metadataDictionaryRoundTrip() throws {
        let metadata = TransferMetadata(
            kind: .chapter,
            bookID: UUID(),
            chapterNumber: 4,
            duration: 3_061.2,
            byteCount: 24_500_000
        )

        let dictionary = metadata.dictionary
        #expect(dictionary[SyncKeys.metadata] is Data)
        #expect(TransferMetadata(dictionary: dictionary) == metadata)
    }

    @Test("Cover metadata keeps its empty chapter fields")
    func coverMetadataRoundTrip() throws {
        let metadata = TransferMetadata(kind: .cover, bookID: UUID())
        let decoded = TransferMetadata(dictionary: metadata.dictionary)

        #expect(decoded == metadata)
        #expect(decoded?.chapterNumber == nil)
    }

    @Test("A dictionary without the payload key is rejected")
    func metadataRejectsJunk() {
        #expect(TransferMetadata(dictionary: [:]) == nil)
        #expect(TransferMetadata(dictionary: [SyncKeys.metadata: "not data"]) == nil)
    }
}
