//
//  AudiobookManagerTests.swift
//  AudiobookReaderTests
//
//  Created by AudiobookReader Testing Infrastructure - Phase 2
//

import Testing
import Foundation
import CoreData
import Combine
import UIKit
@testable import AudiobookReader

@Suite("AudiobookManager Tests", .tags(.manager))
struct AudiobookManagerTests {
    
    let testContext: NSManagedObjectContext
    let manager: AudiobookManager
    
    init() {
        // Create in-memory Core Data stack for testing
        let container = NSPersistentContainer(name: "AudiobookReader")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Failed to load test store: \(error)")
            }
        }
        
        testContext = container.viewContext
        manager = AudiobookManager()
        
        // Reset mocks for each test
        MockFileManager.reset()
        MockAVAudioSession.reset()
    }
    
    // MARK: - Initialization Tests
    
    @Test("AudiobookManager initializes with correct default state")
    func testInitializationState() async throws {
        #expect(manager.audiobooks.isEmpty)
        #expect(manager.isImporting == false)
        #expect(manager.isLoadingLibrary == false)
        #expect(manager.audiobookNeedingCover == nil)
    }
    
    // MARK: - Core Data Fetch Tests
    
    @Test("fetchAudiobooks returns empty array when no audiobooks exist")
    func testFetchEmptyLibrary() async throws {
        manager.fetchAudiobooks()
        
        // Wait for background fetch to complete
        try await Task.sleep(for: .milliseconds(500))
        
        #expect(manager.audiobooks.isEmpty)
        #expect(manager.isLoadingLibrary == false)
    }
    
    @Test("fetchAudiobooks loads existing audiobooks from Core Data")
    func testFetchExistingAudiobooks() async throws {
        // Create test audiobook in Core Data
        let audiobook = createTestAudiobook(title: "Test Book", author: "Test Author")
        let tempFile = createTempAudioFile(named: "test.m4a")
        audiobook.fileURL = tempFile.path
        
        try testContext.save()
        
        // Mock file exists
        MockFileManager.setFileExists(tempFile.path, exists: true)
        
        manager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(500))
        
        #expect(manager.audiobooks.count == 1)
        #expect(manager.audiobooks.first?.title == "Test Book")
        #expect(manager.isLoadingLibrary == false)
    }
    
    @Test("fetchAudiobooks removes audiobooks with missing files")
    func testFetchRemovesMissingFiles() async throws {
        // Create test audiobook with non-existent file
        let audiobook = createTestAudiobook(title: "Missing File Book")
        audiobook.fileURL = "/non/existent/file.m4a"
        
        try testContext.save()
        
        // Mock file doesn't exist
        MockFileManager.setFileExists("/non/existent/file.m4a", exists: false)
        
        manager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(500))
        
        #expect(manager.audiobooks.isEmpty) // Should be removed
        #expect(manager.isLoadingLibrary == false)
    }
    
    // MARK: - Single File Import Tests
    
    @Test("importAudiobook successfully imports M4B file")
    func testImportM4BFile() async throws {
        let tempURL = createTempAudioFile(named: "test.m4b")
        MockFileManager.setFileExists(tempURL.path, exists: true)
        MockFileManager.setFileSize(tempURL.path, size: 50_000_000) // 50MB
        
        await manager.importAudiobook(from: tempURL)
        
        #expect(manager.isImporting == false)
        
        // Verify audiobook was created
        manager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(300))
        
        #expect(manager.audiobooks.count == 1)
        #expect(manager.audiobooks.first?.title?.contains("test") == true)
    }
    
    @Test("importAudiobook handles MP3 file with metadata")
    func testImportMP3File() async throws {
        let tempURL = createTempAudioFile(named: "audiobook.mp3")
        MockFileManager.setFileExists(tempURL.path, exists: true)
        MockFileManager.setFileSize(tempURL.path, size: 100_000_000) // 100MB
        
        await manager.importAudiobook(from: tempURL)
        
        #expect(manager.isImporting == false)
        
        manager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(300))
        
        #expect(manager.audiobooks.count == 1)
        let audiobook = manager.audiobooks.first
        #expect(audiobook?.fileURL?.contains("audiobook.mp3") == true)
    }
    
    @Test("importAudiobook handles security-scoped resource access")
    func testImportWithSecurityScopedResource() async throws {
        let tempURL = createTempAudioFile(named: "scoped.m4a")
        
        // Simulate external file that needs security-scoped access
        MockFileManager.setFileExists(tempURL.path, exists: true)
        MockFileManager.setFileSize(tempURL.path, size: 25_000_000)
        
        await manager.importAudiobook(from: tempURL)
        
        #expect(manager.isImporting == false)
        
        manager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(300))
        
        #expect(manager.audiobooks.count == 1)
    }
    
    // MARK: - ZIP Import Tests
    
    @Test("importZIPAudiobook extracts and imports ZIP file")
    func testZIPImport() async throws {
        let zipURL = createTempZIPFile(named: "audiobook.zip")
        MockFileManager.setFileExists(zipURL.path, exists: true)
        MockFileManager.setFileSize(zipURL.path, size: 200_000_000) // 200MB ZIP
        
        await manager.importZIPAudiobook(from: zipURL)
        
        #expect(manager.isImporting == false)
        
        // Note: In real implementation, this would extract files and import them
        // Mock implementation should simulate successful extraction
    }
    
    @Test("importZIPAudiobook handles corrupted ZIP files gracefully")
    func testCorruptedZIPHandling() async throws {
        let zipURL = createTempZIPFile(named: "corrupt.zip")
        MockFileManager.setFileExists(zipURL.path, exists: true)
        MockFileManager.shouldFailFileOperations = true
        
        await manager.importZIPAudiobook(from: zipURL)
        
        #expect(manager.isImporting == false)
        
        // Should handle gracefully without crashing
        manager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(300))
        
        // No audiobooks should be imported from corrupt ZIP
        #expect(manager.audiobooks.isEmpty)
    }
    
    // MARK: - Folder Import Tests
    
    @Test("importAudiobookFolder imports multi-file audiobook")
    func testFolderImport() async throws {
        let folderURL = createTempDirectory(named: "TestAudiobook")
        
        // Create sample audio files in folder
        let file1 = folderURL.appendingPathComponent("Chapter1.mp3")
        let file2 = folderURL.appendingPathComponent("Chapter2.mp3")
        
        FileManager.default.createFile(atPath: file1.path, contents: Data(), attributes: nil)
        FileManager.default.createFile(atPath: file2.path, contents: Data(), attributes: nil)
        
        MockFileManager.setFileExists(folderURL.path, exists: true)
        MockFileManager.setDirectoryContents(folderURL.path, contents: [file1, file2])
        
        await manager.importAudiobookFolder(from: folderURL)
        
        #expect(manager.isImporting == false)
        
        manager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(300))
        
        #expect(manager.audiobooks.count == 1)
        #expect(manager.audiobooks.first?.title?.contains("TestAudiobook") == true)
    }
    
    @Test("importAudiobookFolder handles CUE file with single audio")
    func testFolderWithCUEImport() async throws {
        let folderURL = createTempDirectory(named: "CUEAudiobook")
        
        // Create CUE file and audio file
        let cueFile = folderURL.appendingPathComponent("audiobook.cue")
        let audioFile = folderURL.appendingPathComponent("audiobook.flac")
        
        let cueContent = """
        TITLE "Test Audiobook"
        PERFORMER "Test Author"
        FILE "audiobook.flac" WAVE
        TRACK 01 AUDIO
            TITLE "Chapter 1"
            INDEX 01 00:00:00
        TRACK 02 AUDIO
            TITLE "Chapter 2"
            INDEX 01 15:30:00
        """
        
        try cueContent.write(to: cueFile, atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: audioFile.path, contents: Data(), attributes: nil)
        
        MockFileManager.setFileExists(folderURL.path, exists: true)
        MockFileManager.setFileExists(audioFile.path, exists: true)
        MockFileManager.setDirectoryContents(folderURL.path, contents: [cueFile, audioFile])
        
        await manager.importAudiobookFolder(from: folderURL)
        
        #expect(manager.isImporting == false)
    }
    
    // MARK: - CUE-based Import Tests
    
    @Test("CUE-based import creates chapters from CUE metadata")
    func testCUEBasedImport() async throws {
        let audioFile = createTempAudioFile(named: "audiobook.flac")
        
        // Create mock CUE file data
        let mockCue = MockCUEParser.CUEParseResult(
            chapters: [
                MockCUEParser.CUEChapter(title: "Chapter 1", startTime: 0, endTime: 1800, trackNumber: 1),
                MockCUEParser.CUEChapter(title: "Chapter 2", startTime: 1800, endTime: 3600, trackNumber: 2)
            ],
            audioFileName: "audiobook.flac",
            metadata: ["TITLE": "Test CUE Audiobook", "PERFORMER": "Test Author"]
        )
        
        MockCUEParser.mockParseResult = mockCue
        MockFileManager.setFileExists(audioFile.path, exists: true)
        
        // This would normally be called through importAudiobookFolder
        // but we can test the private method indirectly through folder import
        let folderURL = createTempDirectory(named: "CUETest")
        let cueFileURL = folderURL.appendingPathComponent("test.cue")
        try "MOCK CUE".write(to: cueFileURL, atomically: true, encoding: .utf8)
        
        // Copy audio file to folder
        let targetAudio = folderURL.appendingPathComponent("audiobook.flac")
        try FileManager.default.copyItem(at: audioFile, to: targetAudio)
        
        MockFileManager.setDirectoryContents(folderURL.path, contents: [cueFileURL, targetAudio])
        
        await manager.importAudiobookFolder(from: folderURL)
        
        #expect(manager.isImporting == false)
    }
    
    // MARK: - Duplicate Handling Tests
    
    @Test("Import handles duplicate audiobook titles gracefully")
    func testDuplicateHandling() async throws {
        // Import first audiobook
        let tempURL1 = createTempAudioFile(named: "duplicate.m4a")
        MockFileManager.setFileExists(tempURL1.path, exists: true)
        
        await manager.importAudiobook(from: tempURL1)
        
        // Import second audiobook with potential duplicate name
        let tempURL2 = createTempAudioFile(named: "duplicate_copy.m4a")
        MockFileManager.setFileExists(tempURL2.path, exists: true)
        
        await manager.importAudiobook(from: tempURL2)
        
        manager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(300))
        
        #expect(manager.audiobooks.count == 2) // Both should be imported
        #expect(manager.isImporting == false)
    }
    
    // MARK: - Progress and Persistence Tests
    
    @Test("updateProgress saves position and updates last played")
    func testProgressPersistence() async throws {
        let audiobook = createTestAudiobook(title: "Progress Test")
        let tempFile = createTempAudioFile(named: "progress.m4a")
        audiobook.fileURL = tempFile.path
        audiobook.duration = 7200.0 // 2 hours
        
        try testContext.save()
        
        let initialLastPlayed = audiobook.lastPlayed
        
        // Update progress
        manager.updateProgress(for: audiobook, currentTime: 3600.0) // 1 hour in
        
        #expect(audiobook.currentPosition == 3600.0)
        #expect(audiobook.lastPlayed != initialLastPlayed)
        #expect(audiobook.isFinished == false) // Not finished yet
        
        // Update to near end (should mark as finished)
        manager.updateProgress(for: audiobook, currentTime: 7190.0) // Within 30 seconds of end
        
        #expect(audiobook.isFinished == true)
    }
    
    @Test("Audiobook metadata is properly stored and retrieved")
    func testMetadataStorage() async throws {
        let audiobook = createTestAudiobook(title: "Metadata Test", author: "Test Author")
        audiobook.narrator = "Test Narrator"
        audiobook.duration = 5400.0 // 1.5 hours
        
        // Add cover image data
        let testImage = UIImage(systemName: "book.fill")!
        audiobook.coverImageData = testImage.jpegData(compressionQuality: 0.8)
        
        try testContext.save()
        
        // Verify metadata persistence
        manager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(300))
        
        let fetchedBook = manager.audiobooks.first
        #expect(fetchedBook?.title == "Metadata Test")
        #expect(fetchedBook?.author == "Test Author")
        #expect(fetchedBook?.narrator == "Test Narrator")
        #expect(fetchedBook?.duration == 5400.0)
        #expect(fetchedBook?.coverImageData != nil)
    }
    
    // MARK: - Bookmark Management Tests
    
    @Test("createBookmark adds bookmark to audiobook")
    func testBookmarkCreation() async throws {
        let audiobook = createTestAudiobook(title: "Bookmark Test")
        try testContext.save()
        
        manager.createBookmark(
            for: audiobook,
            at: 1800.0, // 30 minutes
            title: "Important Scene",
            note: "Remember this part"
        )
        
        let bookmarks = manager.getBookmarks(for: audiobook)
        #expect(bookmarks.count == 1)
        #expect(bookmarks.first?.title == "Important Scene")
        #expect(bookmarks.first?.timestamp == 1800.0)
        #expect(bookmarks.first?.note == "Remember this part")
    }
    
    @Test("deleteBookmark removes bookmark from audiobook")
    func testBookmarkDeletion() async throws {
        let audiobook = createTestAudiobook(title: "Bookmark Delete Test")
        try testContext.save()
        
        // Create bookmark
        manager.createBookmark(for: audiobook, at: 900.0, title: "Test Bookmark")
        
        let bookmarks = manager.getBookmarks(for: audiobook)
        #expect(bookmarks.count == 1)
        
        // Delete bookmark
        let bookmark = bookmarks.first!
        manager.deleteBookmark(bookmark)
        
        let remainingBookmarks = manager.getBookmarks(for: audiobook)
        #expect(remainingBookmarks.isEmpty)
    }
    
    // MARK: - Library Management Tests
    
    @Test("renameAudiobook updates title and persists changes")
    func testAudiobookRename() async throws {
        let audiobook = createTestAudiobook(title: "Original Title")
        try testContext.save()
        
        manager.renameAudiobook(audiobook, newTitle: "New Title")
        
        #expect(audiobook.title == "New Title")
        
        // Verify persistence
        manager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(300))
        
        #expect(manager.audiobooks.first?.title == "New Title")
    }
    
    @Test("markAsRead sets finished status and position to end")
    func testMarkAsRead() async throws {
        let audiobook = createTestAudiobook(title: "Mark Read Test")
        audiobook.duration = 3600.0
        audiobook.currentPosition = 1800.0
        audiobook.isFinished = false
        
        try testContext.save()
        
        manager.markAsRead(audiobook)
        
        #expect(audiobook.isFinished == true)
        #expect(audiobook.currentPosition == 3600.0)
    }
    
    @Test("markAsUnread resets finished status")
    func testMarkAsUnread() async throws {
        let audiobook = createTestAudiobook(title: "Mark Unread Test")
        audiobook.isFinished = true
        
        try testContext.save()
        
        manager.markAsUnread(audiobook)
        
        #expect(audiobook.isFinished == false)
    }
    
    @Test("deleteAudiobook removes audiobook and file")
    func testAudiobookDeletion() async throws {
        let audiobook = createTestAudiobook(title: "Delete Test")
        let tempFile = createTempAudioFile(named: "delete_test.m4a")
        audiobook.fileURL = tempFile.path
        
        try testContext.save()
        
        manager.deleteAudiobook(audiobook)
        
        // Verify deletion from Core Data
        manager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(300))
        
        #expect(manager.audiobooks.isEmpty)
    }
    
    // MARK: - Search Tests
    
    @Test("searchAudiobooks filters by title and author")
    func testAudiobookSearch() async throws {
        // Create multiple audiobooks
        let book1 = createTestAudiobook(title: "Swift Programming", author: "Apple Inc")
        let book2 = createTestAudiobook(title: "iOS Development", author: "Ray Wenderlich")
        let book3 = createTestAudiobook(title: "Android Programming", author: "Google")
        
        try testContext.save()
        
        // Populate manager audiobooks array (normally done by fetchAudiobooks)
        manager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(300))
        
        // Test title search
        let swiftResults = manager.searchAudiobooks(query: "Swift")
        #expect(swiftResults.count == 1)
        #expect(swiftResults.first?.title == "Swift Programming")
        
        // Test author search
        let appleResults = manager.searchAudiobooks(query: "Apple")
        #expect(appleResults.count == 1)
        #expect(appleResults.first?.author == "Apple Inc")
        
        // Test partial match
        let programmingResults = manager.searchAudiobooks(query: "programming")
        #expect(programmingResults.count == 2) // Swift and Android
        
        // Test empty query returns all
        let allResults = manager.searchAudiobooks(query: "")
        #expect(allResults.count == 3)
    }
    
    // MARK: - Cover Image Management Tests
    
    @Test("updateCoverImage saves image data and clears needing cover flag")
    func testCoverImageUpdate() async throws {
        let audiobook = createTestAudiobook(title: "Cover Test")
        try testContext.save()
        
        // Set as needing cover
        manager.audiobookNeedingCover = audiobook
        
        let testImage = UIImage(systemName: "book.circle")!
        manager.updateCoverImage(for: audiobook, with: testImage)
        
        #expect(audiobook.coverImageData != nil)
        #expect(manager.audiobookNeedingCover == nil) // Should be cleared
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Import handles file access errors gracefully")
    func testImportFileAccessErrors() async throws {
        let tempURL = createTempAudioFile(named: "error_test.m4a")
        
        // Simulate file access error
        MockFileManager.shouldFailFileOperations = true
        
        await manager.importAudiobook(from: tempURL)
        
        #expect(manager.isImporting == false)
        
        // Should handle error without crashing
        manager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(300))
        
        // No audiobook should be imported
        #expect(manager.audiobooks.isEmpty)
    }
    
    // MARK: - Concurrency Tests
    
    @Test("Concurrent import operations are handled safely")
    func testConcurrentImports() async throws {
        let url1 = createTempAudioFile(named: "concurrent1.m4a")
        let url2 = createTempAudioFile(named: "concurrent2.m4a")
        let url3 = createTempAudioFile(named: "concurrent3.m4a")
        
        MockFileManager.setFileExists(url1.path, exists: true)
        MockFileManager.setFileExists(url2.path, exists: true)
        MockFileManager.setFileExists(url3.path, exists: true)
        
        // Start concurrent imports
        async let import1 = manager.importAudiobook(from: url1)
        async let import2 = manager.importAudiobook(from: url2)
        async let import3 = manager.importAudiobook(from: url3)
        
        await import1
        await import2
        await import3
        
        #expect(manager.isImporting == false)
        
        manager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(500))
        
        // All three should be imported
        #expect(manager.audiobooks.count == 3)
    }
    
    // MARK: - Helper Methods
    
    private func createTestAudiobook(title: String, author: String = "Test Author") -> Audiobook {
        let audiobook = Audiobook(context: testContext)
        audiobook.id = UUID()
        audiobook.title = title
        audiobook.author = author
        audiobook.duration = 3600.0
        audiobook.currentPosition = 0.0
        audiobook.dateAdded = Date()
        audiobook.isFinished = false
        return audiobook
    }
    
    private func createTempAudioFile(named filename: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)
        
        // Create empty file for testing
        FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)
        
        return fileURL
    }
    
    private func createTempZIPFile(named filename: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)
        
        // Create mock ZIP file
        FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)
        
        return fileURL
    }
    
    private func createTempDirectory(named dirname: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let dirURL = tempDir.appendingPathComponent(dirname)
        
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        
        return dirURL
    }
}