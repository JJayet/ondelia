import Foundation
import SwiftData
import Testing
@testable import Isora

/// The store runs on its own SwiftData context, so these tests deliberately do not touch the
/// main context: everything crosses the actor boundary as a value.
@Suite("TranscriptionStore")
struct TranscriptionStoreTests {

    /// A fresh in-memory container per test, so one test's rows cannot leak into another.
    private func makeStore() throws -> (TranscriptionStore, ModelContainer) {
        let schema = Schema([
            AudiobookModel.self,
            BookmarkModel.self,
            ChapterModel.self,
            ChapterTranscriptionModel.self,
            TranscriptWindowModel.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
        return (TranscriptionStore(modelContainer: container), container)
    }

    private func request(_ bookID: UUID, track: Int = 0, start: Double = 0, end: Double = 600) -> TranscriptionRequest {
        TranscriptionRequest(
            audiobookID: bookID,
            url: URL(fileURLWithPath: "/tmp/book.m4b"),
            trackIndex: track,
            start: start,
            end: end,
            trackStart: 0,
            title: nil,
            language: nil
        )
    }

    @MainActor
    private func insertBook(_ container: ModelContainer, id: UUID) throws {
        let book = AudiobookModel(id: id, title: "Book", author: "Author", duration: 100)
        container.mainContext.insert(book)
        try container.mainContext.save()
    }

    @Test("A saved transcript comes back with its text, language and segments")
    func roundTrip() async throws {
        let (store, container) = try makeStore()
        let bookID = UUID()
        try await insertBook(container, id: bookID)

        let result = TranscriptionResult(
            text: "Once upon a time",
            segments: [
                TranscriptionSegment(text: "Once", start: 0, end: 0.5),
                TranscriptionSegment(text: " upon", start: 0.5, end: 0.9)
            ],
            language: "en"
        )

        await store.save(result, for: request(bookID, track: Int(3)), engine: "SpeechAnalyzer")
        let cached = await store.cachedResult(for: request(bookID, track: Int(3)), language: "en")

        #expect(cached?.text == "Once upon a time")
        #expect(cached?.language == "en")
        #expect(cached?.segments == result.segments)
    }

    @Test("Nothing is cached for a chapter that was never transcribed")
    func missingChapterIsNil() async throws {
        let (store, container) = try makeStore()
        let bookID = UUID()
        try await insertBook(container, id: bookID)

        await store.save(
            TranscriptionResult(text: "chapter one", segments: [], language: "en"),
            for: request(bookID, track: Int(0)), engine: "SpeechAnalyzer"
        )

        #expect(await store.cachedResult(for: request(bookID, track: Int(1)), language: "en") == nil)
        #expect(await store.cachedResult(for: request(UUID(), track: Int(0)), language: "en") == nil)
    }

    @Test("Transcribing a chapter again replaces the old transcript rather than duplicating it")
    func saveReplaces() async throws {
        let (store, container) = try makeStore()
        let bookID = UUID()
        try await insertBook(container, id: bookID)

        await store.save(
            TranscriptionResult(text: "first pass", segments: [], language: "en"),
            for: request(bookID, track: Int(2)), engine: "SpeechAnalyzer"
        )
        await store.save(
            TranscriptionResult(text: "second pass", segments: [], language: "en"),
            for: request(bookID, track: Int(2)), engine: "SpeechAnalyzer"
        )

        #expect(await store.cachedResult(for: request(bookID, track: Int(2)), language: "en")?.text == "second pass")

        // Exactly one row, so the cache cannot grow every time a chapter is re-run.
        // Counted inside the main actor: a PersistentModel cannot cross out of it, which is
        // the whole reason the store hands back values instead of rows.
        let rowCount = try await MainActor.run {
            try container.mainContext.fetchCount(FetchDescriptor<TranscriptWindowModel>())
        }
        #expect(rowCount == 1)
    }

    @Test("A transcript for a book that is not in the store is dropped, not orphaned")
    func unknownBookIsRejected() async throws {
        let (store, _) = try makeStore()
        let unknown = UUID()

        await store.save(
            TranscriptionResult(text: "nowhere", segments: [], language: "en"),
            for: request(unknown, track: Int(0)), engine: "SpeechAnalyzer"
        )

        #expect(await store.cachedResult(for: request(unknown, track: Int(0)), language: "en") == nil)
    }

    @Test("Chapters of the same book are cached independently")
    func chaptersAreIndependent() async throws {
        let (store, container) = try makeStore()
        let bookID = UUID()
        try await insertBook(container, id: bookID)

        for chapter in 0..<3 {
            await store.save(
                TranscriptionResult(text: "chapter \(chapter)", segments: [], language: "en"),
                for: request(bookID, track: Int(chapter)), engine: "SpeechAnalyzer"
            )
        }

        for chapter in 0..<3 {
            #expect(await store.cachedResult(for: request(bookID, track: Int(chapter)), language: "en")?.text
                    == "chapter \(chapter)")
        }
    }
}
