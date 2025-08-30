//
//  SimpleCoreDataTests.swift
//  AudiobookReaderTests
//
//  Created by AudiobookReader Testing Infrastructure
//

import Testing
import CoreData
@testable import AudiobookReader

struct SimpleCoreDataTests {
    
    // MARK: - Test Setup
    
    let persistenceController = PersistenceController.preview
    
    var context: NSManagedObjectContext {
        return persistenceController.container.viewContext
    }
    
    // MARK: - Basic Audiobook Tests
    
    @Test("Audiobook should be created with required properties")
    func audiobookBasicCreation() async throws {
        let audiobook = Audiobook(context: context)
        let id = UUID()
        
        audiobook.id = id
        audiobook.title = "Test Audiobook"
        audiobook.author = "Test Author"
        audiobook.narrator = "Test Narrator"
        audiobook.duration = 3600.0
        audiobook.currentPosition = 450.0
        audiobook.isFinished = false
        audiobook.dateAdded = Date()
        
        try context.save()
        
        #expect(audiobook.id == id)
        #expect(audiobook.title == "Test Audiobook")
        #expect(audiobook.author == "Test Author")
        #expect(audiobook.narrator == "Test Narrator")
        #expect(audiobook.duration == 3600.0)
        #expect(audiobook.currentPosition == 450.0)
        #expect(audiobook.isFinished == false)
        #expect(audiobook.dateAdded != nil)
    }
    
    @Test("Audiobook should handle optional properties")
    func audiobookOptionalProperties() async throws {
        let audiobook = Audiobook(context: context)
        audiobook.id = UUID()
        audiobook.title = "Test Audiobook"
        
        // Test optional properties default values
        #expect(audiobook.author == nil || audiobook.author?.isEmpty == true)
        #expect(audiobook.narrator == nil || audiobook.narrator?.isEmpty == true)
        #expect(audiobook.coverImageData == nil)
        #expect(audiobook.fileURL == nil)
        #expect(audiobook.dateAdded == nil)
        #expect(audiobook.lastPlayed == nil)
        #expect(audiobook.currentPosition == 0.0)
        #expect(audiobook.duration == 0.0)
        #expect(audiobook.isFinished == false)
    }
    
    // MARK: - Chapter Tests
    
    @Test("Chapter should be created with required properties")
    func chapterBasicCreation() async throws {
        let audiobook = Audiobook(context: context)
        audiobook.id = UUID()
        audiobook.title = "Test Audiobook"
        
        let chapter = Chapter(context: context)
        let chapterId = UUID()
        
        chapter.id = chapterId
        chapter.title = "Test Chapter"
        chapter.chapterNumber = 1
        chapter.startTime = 0
        chapter.endTime = 1800
        chapter.audiobook = audiobook
        
        try context.save()
        
        #expect(chapter.id == chapterId)
        #expect(chapter.title == "Test Chapter")
        #expect(chapter.chapterNumber == 1)
        #expect(chapter.startTime == 0)
        #expect(chapter.endTime == 1800)
        #expect(chapter.audiobook == audiobook)
    }
    
    @Test("Chapter should maintain audiobook relationship")
    func chapterAudiobookRelationship() async throws {
        let audiobook = Audiobook(context: context)
        audiobook.id = UUID()
        audiobook.title = "Test Audiobook"
        
        let chapter = Chapter(context: context)
        chapter.id = UUID()
        chapter.title = "Test Chapter"
        chapter.audiobook = audiobook
        
        try context.save()
        
        #expect(chapter.audiobook == audiobook)
        #expect(audiobook.chapters?.contains(chapter) == true)
    }
    
    // MARK: - Bookmark Tests
    
    @Test("Bookmark should be created with required properties")
    func bookmarkBasicCreation() async throws {
        let audiobook = Audiobook(context: context)
        audiobook.id = UUID()
        audiobook.title = "Test Audiobook"
        
        let bookmark = Bookmark(context: context)
        let bookmarkId = UUID()
        let creationDate = Date()
        
        bookmark.id = bookmarkId
        bookmark.title = "Important Quote"
        bookmark.note = "This is a significant passage"
        bookmark.timestamp = 1500.0
        bookmark.dateCreated = creationDate
        bookmark.audiobook = audiobook
        
        try context.save()
        
        #expect(bookmark.id == bookmarkId)
        #expect(bookmark.title == "Important Quote")
        #expect(bookmark.note == "This is a significant passage")
        #expect(bookmark.timestamp == 1500.0)
        #expect(bookmark.dateCreated == creationDate)
        #expect(bookmark.audiobook == audiobook)
    }
    
    @Test("Bookmark should handle optional note")
    func bookmarkOptionalNote() async throws {
        let audiobook = Audiobook(context: context)
        audiobook.id = UUID()
        audiobook.title = "Test Audiobook"
        
        let bookmark = Bookmark(context: context)
        bookmark.id = UUID()
        bookmark.title = "Quick Bookmark"
        bookmark.timestamp = 1000.0
        bookmark.audiobook = audiobook
        // Note is nil
        
        try context.save()
        
        #expect(bookmark.note == nil)
        #expect(bookmark.title == "Quick Bookmark")
    }
    
    // MARK: - Relationship Tests
    
    @Test("Audiobook should handle chapters relationship")
    func audiobookChaptersRelationship() async throws {
        let audiobook = Audiobook(context: context)
        audiobook.id = UUID()
        audiobook.title = "Test Audiobook"
        audiobook.duration = 3600.0
        
        // Create chapters
        let chapter1 = Chapter(context: context)
        chapter1.id = UUID()
        chapter1.title = "Chapter 1"
        chapter1.chapterNumber = 1
        chapter1.startTime = 0
        chapter1.endTime = 1800
        chapter1.audiobook = audiobook
        
        let chapter2 = Chapter(context: context)
        chapter2.id = UUID()
        chapter2.title = "Chapter 2"
        chapter2.chapterNumber = 2
        chapter2.startTime = 1800
        chapter2.endTime = 3600
        chapter2.audiobook = audiobook
        
        try context.save()
        
        // Test relationship
        #expect(audiobook.chapters?.count == 2)
        
        if let chaptersSet = audiobook.chapters,
           let chapters = Array(chaptersSet) as? [Chapter] {
            #expect(chapters.count == 2)
            
            let sortedChapters = chapters.sorted { $0.chapterNumber < $1.chapterNumber }
            #expect(sortedChapters[0].title == "Chapter 1")
            #expect(sortedChapters[1].title == "Chapter 2")
        }
    }
    
    // MARK: - Persistence Tests
    
    @Test("Data should persist across context saves")
    func dataPersistence() async throws {
        let audiobook = Audiobook(context: context)
        let audiobookId = UUID()
        
        audiobook.id = audiobookId
        audiobook.title = "Persistent Audiobook"
        audiobook.author = "Test Author"
        audiobook.duration = 7200.0
        
        try context.save()
        
        // Clear context and refetch
        context.reset()
        
        let fetchRequest: NSFetchRequest<Audiobook> = Audiobook.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", audiobookId as CVarArg)
        
        let fetchedAudiobooks = try context.fetch(fetchRequest)
        
        #expect(fetchedAudiobooks.count == 1)
        let fetchedAudiobook = fetchedAudiobooks[0]
        #expect(fetchedAudiobook.id == audiobookId)
        #expect(fetchedAudiobook.title == "Persistent Audiobook")
        #expect(fetchedAudiobook.author == "Test Author")
        #expect(fetchedAudiobook.duration == 7200.0)
    }
    
    @Test("Cascade deletion should work correctly")
    func cascadeDeletion() async throws {
        let audiobook = Audiobook(context: context)
        audiobook.id = UUID()
        audiobook.title = "Deletable Audiobook"
        
        let chapter = Chapter(context: context)
        chapter.id = UUID()
        chapter.title = "Deletable Chapter"
        chapter.audiobook = audiobook
        
        let bookmark = Bookmark(context: context)
        bookmark.id = UUID()
        bookmark.title = "Deletable Bookmark"
        bookmark.timestamp = 300.0
        bookmark.audiobook = audiobook
        
        try context.save()
        
        // Verify objects exist
        #expect(audiobook.chapters?.count == 1)
        #expect(audiobook.bookmarks?.count == 1)
        
        // Delete audiobook
        context.delete(audiobook)
        try context.save()
        
        // Verify cascade deletion worked
        let chapterFetch: NSFetchRequest<Chapter> = Chapter.fetchRequest()
        let remainingChapters = try context.fetch(chapterFetch)
        
        let bookmarkFetch: NSFetchRequest<Bookmark> = Bookmark.fetchRequest()
        let remainingBookmarks = try context.fetch(bookmarkFetch)
        
        #expect(remainingChapters.isEmpty)
        #expect(remainingBookmarks.isEmpty)
    }
}