import Testing
import Foundation
import SwiftData
@testable import Isora

@MainActor
struct SwiftDataModelTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainer(
            for: AudiobookModel.self, BookmarkModel.self, ChapterModel.self, ChapterTranscriptionModel.self,
            // `.none`: the default is `.automatic`, which reaches for CloudKit now that the app has the entitlement.
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    @Test("Audiobook stores its properties")
    func audiobookBasicCreation() throws {
        let id = UUID()
        let audiobook = AudiobookModel(id: id, title: "Test Audiobook", author: "Test Author", narrator: "Test Narrator",
                                       duration: 3600, currentPosition: 450)
        context.insert(audiobook)
        try context.save()

        #expect(audiobook.id == id)
        #expect(audiobook.title == "Test Audiobook")
        #expect(audiobook.author == "Test Author")
        #expect(audiobook.narrator == "Test Narrator")
        #expect(audiobook.duration == 3600)
        #expect(audiobook.currentPosition == 450)
        #expect(audiobook.isFinished == false)
    }

    @Test("Audiobook defaults")
    func audiobookDefaults() {
        let audiobook = AudiobookModel(title: "Test Audiobook")
        #expect(audiobook.author == nil)
        #expect(audiobook.narrator == nil)
        #expect(audiobook.coverImageData == nil)
        #expect(audiobook.fileURL == nil)
        #expect(audiobook.lastPlayed == .distantPast)
        #expect(audiobook.currentPosition == 0)
        #expect(audiobook.duration == 0)
        #expect(audiobook.isFinished == false)
        #expect(audiobook.chapters.isEmpty)
        #expect(audiobook.bookmarks.isEmpty)
    }

    @Test("Chapter and bookmark relationships link both ways")
    func relationships() throws {
        let audiobook = AudiobookModel(title: "Test Audiobook", duration: 3600)
        context.insert(audiobook)

        let chapter1 = ChapterModel(title: "Chapter 1", chapterNumber: 1, startTime: 0, endTime: 1800)
        let chapter2 = ChapterModel(title: "Chapter 2", chapterNumber: 2, startTime: 1800, endTime: 3600)
        chapter2.audiobook = audiobook
        chapter1.audiobook = audiobook

        let bookmark = BookmarkModel(title: "Important Quote", note: "Passage", timestamp: 1500, dateCreated: Date())
        bookmark.audiobook = audiobook
        try context.save()

        #expect(audiobook.chapters.count == 2)
        let sorted = audiobook.chapters.sorted { $0.chapterNumber < $1.chapterNumber }
        #expect(sorted.map(\.title) == ["Chapter 1", "Chapter 2"])
        #expect(audiobook.bookmarks.count == 1)
        #expect(audiobook.bookmarks.first?.note == "Passage")
        #expect(bookmark.audiobook?.id == audiobook.id)
    }

    @Test("Saved audiobook can be fetched by id")
    func dataPersistence() throws {
        let id = UUID()
        context.insert(AudiobookModel(id: id, title: "Persistent Audiobook", author: "Test Author", duration: 7200))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<AudiobookModel>(predicate: #Predicate { $0.id == id }))
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Persistent Audiobook")
        #expect(fetched.first?.duration == 7200)
    }

    @Test("Deleting an audiobook cascades to chapters and bookmarks")
    func cascadeDeletion() throws {
        let audiobook = AudiobookModel(title: "Deletable")
        context.insert(audiobook)
        let chapter = ChapterModel(title: "Deletable Chapter")
        chapter.audiobook = audiobook
        let bookmark = BookmarkModel(title: "Deletable Bookmark", timestamp: 300)
        bookmark.audiobook = audiobook
        try context.save()

        context.delete(audiobook)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<ChapterModel>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<BookmarkModel>()).isEmpty)
    }
}
