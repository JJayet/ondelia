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
            ChapterTranscriptionModel.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return (TranscriptionStore(modelContainer: container), container)
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
            language: "en-US"
        )

        await store.save(result, audiobookID: bookID, chapterIndex: 3, engine: "SpeechAnalyzer")
        let cached = await store.cachedResult(audiobookID: bookID, chapterIndex: 3)

        #expect(cached?.text == "Once upon a time")
        #expect(cached?.language == "en-US")
        #expect(cached?.segments == result.segments)
    }

    @Test("Nothing is cached for a chapter that was never transcribed")
    func missingChapterIsNil() async throws {
        let (store, container) = try makeStore()
        let bookID = UUID()
        try await insertBook(container, id: bookID)

        await store.save(
            TranscriptionResult(text: "chapter one", segments: [], language: "en"),
            audiobookID: bookID, chapterIndex: 0, engine: "SpeechAnalyzer"
        )

        #expect(await store.cachedResult(audiobookID: bookID, chapterIndex: 1) == nil)
        #expect(await store.cachedResult(audiobookID: UUID(), chapterIndex: 0) == nil)
    }

    @Test("Transcribing a chapter again replaces the old transcript rather than duplicating it")
    func saveReplaces() async throws {
        let (store, container) = try makeStore()
        let bookID = UUID()
        try await insertBook(container, id: bookID)

        await store.save(
            TranscriptionResult(text: "first pass", segments: [], language: "en"),
            audiobookID: bookID, chapterIndex: 2, engine: "SpeechAnalyzer"
        )
        await store.save(
            TranscriptionResult(text: "second pass", segments: [], language: "fr"),
            audiobookID: bookID, chapterIndex: 2, engine: "SpeechAnalyzer"
        )

        #expect(await store.cachedResult(audiobookID: bookID, chapterIndex: 2)?.text == "second pass")

        // Exactly one row, so the cache cannot grow every time a chapter is re-run.
        // Counted inside the main actor: a PersistentModel cannot cross out of it, which is
        // the whole reason the store hands back values instead of rows.
        let rowCount = try await MainActor.run {
            try container.mainContext.fetchCount(FetchDescriptor<ChapterTranscriptionModel>())
        }
        #expect(rowCount == 1)
    }

    @Test("A transcript for a book that is not in the store is dropped, not orphaned")
    func unknownBookIsRejected() async throws {
        let (store, _) = try makeStore()
        let unknown = UUID()

        await store.save(
            TranscriptionResult(text: "nowhere", segments: [], language: "en"),
            audiobookID: unknown, chapterIndex: 0, engine: "SpeechAnalyzer"
        )

        #expect(await store.cachedResult(audiobookID: unknown, chapterIndex: 0) == nil)
    }

    @Test("Chapters of the same book are cached independently")
    func chaptersAreIndependent() async throws {
        let (store, container) = try makeStore()
        let bookID = UUID()
        try await insertBook(container, id: bookID)

        for chapter in Int16(0)..<3 {
            await store.save(
                TranscriptionResult(text: "chapter \(chapter)", segments: [], language: "en"),
                audiobookID: bookID, chapterIndex: chapter, engine: "SpeechAnalyzer"
            )
        }

        for chapter in Int16(0)..<3 {
            #expect(await store.cachedResult(audiobookID: bookID, chapterIndex: chapter)?.text
                    == "chapter \(chapter)")
        }
    }
}
