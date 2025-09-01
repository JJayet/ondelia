//
//  ImportWorkflowIntegrationTests.swift
//  AudiobookReaderTests
//
//  Created by AudiobookReader Testing Infrastructure - Phase 2
//

import Testing
import Foundation
import CoreData
import Combine
@testable import AudiobookReader

@Suite("Import Workflow Integration Tests", .tags(.integration))
struct ImportWorkflowIntegrationTests {
    
    let testContext: NSManagedObjectContext
    let audiobookManager: AudiobookManager
    let globalAudioManager: GlobalAudioManager
    
    init() {
        // Create in-memory Core Data stack for integration testing
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
        audiobookManager = AudiobookManager()
        globalAudioManager = GlobalAudioManager.shared
        
        // Reset all mocks
        MockFileManager.reset()
        MockAVAudioSession.reset()
        MockCUEParser.reset()
    }
    
    // MARK: - Complete ZIP Import Workflow Tests
    
    @Test("Complete ZIP import workflow: Extract → Core Data → Engine Setup")
    func testCompleteZIPImportWorkflow() async throws {
        // Setup: Create mock ZIP file with audiobook content
        let zipURL = createMockZIPFile(
            named: "TestAudiobook.zip",
            containing: [
                "Chapter1.mp3": 50_000_000, // 50MB
                "Chapter2.mp3": 45_000_000, // 45MB
                "cover.jpg": 500_000        // 500KB
            ]
        )
        
        MockFileManager.setFileExists(zipURL.path, exists: true)
        
        // Step 1: Import ZIP file
        await audiobookManager.importZIPAudiobook(from: zipURL)
        
        // Verify import completed
        #expect(audiobookManager.isImporting == false)
        
        // Step 2: Verify Core Data persistence
        audiobookManager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(500))
        
        #expect(audiobookManager.audiobooks.count >= 1)
        
        guard let importedBook = audiobookManager.audiobooks.first else {
            Issue.record("No audiobook was imported from ZIP")
            return
        }
        
        #expect(importedBook.title?.contains("TestAudiobook") == true)
        #expect(importedBook.fileURL != nil)
        #expect(importedBook.duration > 0)
        
        // Step 3: Verify audio engine setup
        await globalAudioManager.loadAudiobook(importedBook)
        try await Task.sleep(for: .milliseconds(800))
        
        #expect(globalAudioManager.currentAudiobook?.objectID == importedBook.objectID)
        #expect(globalAudioManager.isReady == true)
        #expect(globalAudioManager.useMultiFileEngine == true) // ZIP typically contains multiple files
        #expect(globalAudioManager.multiFileAudioEngine != nil)
        
        // Step 4: Verify playback readiness
        #expect(globalAudioManager.getDuration() > 0)
        #expect(globalAudioManager.getCurrentTime() >= 0)
        
        // Clean up
        try await cleanupTempFiles()
    }
    
    @Test("ZIP import with nested folder structure")
    func testNestedZIPImportWorkflow() async throws {
        let zipURL = createMockZIPFile(
            named: "NestedAudiobook.zip",
            containing: [
                "Book/Chapter1.mp3": 60_000_000,
                "Book/Chapter2.mp3": 55_000_000,
                "Book/Metadata/cover.png": 800_000,
                "Book/audiobook.cue": 2_000 // CUE file
            ]
        )
        
        MockFileManager.setFileExists(zipURL.path, exists: true)
        
        await audiobookManager.importZIPAudiobook(from: zipURL)
        
        #expect(audiobookManager.isImporting == false)
        
        audiobookManager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(500))
        
        #expect(audiobookManager.audiobooks.count >= 1)
        
        let importedBook = audiobookManager.audiobooks.first!
        #expect(importedBook.fileURL?.contains("Book") == true)
        
        // Test engine loading with nested structure
        await globalAudioManager.loadAudiobook(importedBook)
        try await Task.sleep(for: .milliseconds(500))
        
        #expect(globalAudioManager.isReady == true)
    }
    
    // MARK: - Folder Import Workflow Tests
    
    @Test("Complete folder import workflow: Multi-file → Chapters → Playback")
    func testCompleteFolderImportWorkflow() async throws {
        // Setup: Create folder with multiple audio files
        let folderURL = createMockAudiobookFolder(
            named: "MultiFileAudiobook",
            chapters: [
                ("01 - Introduction.mp3", 1800.0), // 30 minutes
                ("02 - Chapter One.mp3", 2400.0),  // 40 minutes
                ("03 - Chapter Two.mp3", 1800.0),  // 30 minutes
                ("04 - Conclusion.mp3", 900.0)     // 15 minutes
            ]
        )
        
        MockFileManager.setFileExists(folderURL.path, exists: true)
        
        // Step 1: Import folder
        await audiobookManager.importAudiobookFolder(from: folderURL)
        
        #expect(audiobookManager.isImporting == false)
        
        // Step 2: Verify Core Data with chapters
        audiobookManager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(500))
        
        #expect(audiobookManager.audiobooks.count == 1)
        
        let audiobook = audiobookManager.audiobooks.first!
        #expect(audiobook.title?.contains("MultiFileAudiobook") == true)
        #expect(audiobook.chapters?.count == 4)
        
        // Verify chapter ordering and timing
        let chapters = (audiobook.chapters?.allObjects as? [Chapter])?.sorted { $0.chapterNumber < $1.chapterNumber }
        #expect(chapters?.first?.title?.contains("Introduction") == true)
        #expect(chapters?.last?.title?.contains("Conclusion") == true)
        
        // Step 3: Load into audio engine
        await globalAudioManager.loadAudiobook(audiobook)
        try await Task.sleep(for: .milliseconds(500))
        
        #expect(globalAudioManager.useMultiFileEngine == true)
        #expect(globalAudioManager.multiFileAudioEngine != nil)
        #expect(globalAudioManager.isReady == true)
        
        // Step 4: Test chapter navigation
        let totalDuration = globalAudioManager.getDuration()
        #expect(totalDuration >= 6900.0) // Sum of all chapters
        
        // Test seeking to second chapter
        globalAudioManager.seek(to: 1800.0) // End of first chapter
        #expect(globalAudioManager.getCurrentTime() >= 1790.0)
        #expect(globalAudioManager.getCurrentTime() <= 1810.0)
    }
    
    @Test("Folder with cover image import workflow")
    func testFolderWithCoverImageWorkflow() async throws {
        let folderURL = createMockAudiobookFolder(
            named: "BookWithCover",
            chapters: [("audiobook.m4b", 7200.0)], // 2 hours
            includeCover: true
        )
        
        MockFileManager.setFileExists(folderURL.path, exists: true)
        
        await audiobookManager.importAudiobookFolder(from: folderURL)
        
        audiobookManager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(500))
        
        let audiobook = audiobookManager.audiobooks.first!
        #expect(audiobook.coverImageData != nil)
        #expect(audiobook.coverImageData?.count ?? 0 > 0)
        
        // Verify cover doesn't trigger "needing cover" flag
        #expect(audiobookManager.audiobookNeedingCover?.objectID != audiobook.objectID)
    }
    
    // MARK: - CUE File Import Workflow Tests
    
    @Test("Complete CUE import workflow: Parse → Chapters → Single File Engine")
    func testCompleteCUEImportWorkflow() async throws {
        // Setup: Create folder with CUE file and single audio file
        let folderURL = createTempDirectory(named: "CUEAudiobook")
        let audioFile = folderURL.appendingPathComponent("audiobook.flac")
        let cueFile = folderURL.appendingPathComponent("audiobook.cue")
        
        // Create large audio file (simulating full audiobook)
        let audioData = Data(count: 100_000_000) // 100MB
        try audioData.write(to: audioFile)
        
        // Create comprehensive CUE file
        let cueContent = """
        REM GENRE "Science Fiction"
        REM DATE "2023"
        PERFORMER "Isaac Asimov"
        TITLE "Foundation"
        FILE "audiobook.flac" WAVE
          TRACK 01 AUDIO
            TITLE "The Psychohistorians"
            PERFORMER "Isaac Asimov"
            INDEX 01 00:00:00
          TRACK 02 AUDIO
            TITLE "The Encyclopedists"
            PERFORMER "Isaac Asimov"
            INDEX 01 18:45:30
          TRACK 03 AUDIO
            TITLE "The Mayors"
            PERFORMER "Isaac Asimov"
            INDEX 01 42:12:15
          TRACK 04 AUDIO
            TITLE "The Traders"
            PERFORMER "Isaac Asimov"
            INDEX 01 68:30:00
        """
        
        try cueContent.write(to: cueFile, atomically: true, encoding: .utf8)
        
        MockFileManager.setFileExists(folderURL.path, exists: true)
        MockFileManager.setFileExists(audioFile.path, exists: true)
        MockFileManager.setFileExists(cueFile.path, exists: true)
        MockFileManager.setDirectoryContents(folderURL.path, contents: [audioFile, cueFile])
        
        // Step 1: Import folder (should detect CUE + audio)
        await audiobookManager.importAudiobookFolder(from: folderURL)
        
        #expect(audiobookManager.isImporting == false)
        
        // Step 2: Verify single file with CUE-based chapters
        audiobookManager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(500))
        
        #expect(audiobookManager.audiobooks.count == 1)
        
        let audiobook = audiobookManager.audiobooks.first!
        #expect(audiobook.title?.contains("Foundation") == true)
        #expect(audiobook.author?.contains("Asimov") == true)
        #expect(audiobook.fileURL?.contains("audiobook.flac") == true)
        
        // Should have 4 chapters from CUE
        let chapters = audiobook.chapters?.allObjects as? [Chapter]
        #expect(chapters?.count == 4)
        
        // Verify chapter timing
        let sortedChapters = chapters?.sorted { $0.chapterNumber < $1.chapterNumber }
        #expect(sortedChapters?.first?.title == "The Psychohistorians")
        #expect(sortedChapters?.first?.startTime == 0.0)
        
        // Step 3: Load into single file engine (not multi-file)
        await globalAudioManager.loadAudiobook(audiobook)
        try await Task.sleep(for: .milliseconds(500))
        
        #expect(globalAudioManager.useMultiFileEngine == false) // Single file with CUE
        #expect(globalAudioManager.audioEngine != nil)
        #expect(globalAudioManager.multiFileAudioEngine == nil)
        #expect(globalAudioManager.isReady == true)
        
        // Step 4: Test chapter-based seeking
        let totalDuration = globalAudioManager.getDuration()
        #expect(totalDuration > 0)
        
        // Seek to second chapter (18:45:30 = 67530 seconds)
        globalAudioManager.seek(to: 67530.0)
        #expect(globalAudioManager.getCurrentTime() >= 67520.0)
        #expect(globalAudioManager.getCurrentTime() <= 67540.0)
    }
    
    // MARK: - Error Recovery Workflow Tests
    
    @Test("Import workflow handles corrupted files gracefully")
    func testCorruptedFileRecoveryWorkflow() async throws {
        let folderURL = createTempDirectory(named: "CorruptedAudiobook")
        
        // Create corrupted files (empty or invalid data)
        let corruptFile1 = folderURL.appendingPathComponent("corrupt1.mp3")
        let corruptFile2 = folderURL.appendingPathComponent("corrupt2.mp3")
        let validFile = folderURL.appendingPathComponent("valid.mp3")
        
        // Corrupted files - empty data
        try Data().write(to: corruptFile1)
        try Data().write(to: corruptFile2)
        
        // Valid file - some data
        try Data(count: 10_000_000).write(to: validFile) // 10MB
        
        MockFileManager.setFileExists(folderURL.path, exists: true)
        MockFileManager.setDirectoryContents(folderURL.path, contents: [corruptFile1, corruptFile2, validFile])
        
        await audiobookManager.importAudiobookFolder(from: folderURL)
        
        // Should complete without crashing
        #expect(audiobookManager.isImporting == false)
        
        audiobookManager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(500))
        
        // Should either import nothing (if all files are corrupted) or import valid files only
        // The exact behavior depends on implementation, but should not crash
    }
    
    @Test("Import workflow handles missing dependencies")
    func testMissingDependencyWorkflow() async throws {
        let folderURL = createTempDirectory(named: "MissingDepsAudiobook")
        let cueFile = folderURL.appendingPathComponent("audiobook.cue")
        
        // Create CUE file that references non-existent audio file
        let cueContent = """
        PERFORMER "Test Author"
        TITLE "Missing Audio Test"
        FILE "nonexistent.flac" WAVE
          TRACK 01 AUDIO
            TITLE "Chapter 1"
            INDEX 01 00:00:00
        """
        
        try cueContent.write(to: cueFile, atomically: true, encoding: .utf8)
        
        MockFileManager.setFileExists(folderURL.path, exists: true)
        MockFileManager.setFileExists(cueFile.path, exists: true)
        // Note: Not setting the audio file as existing
        MockFileManager.setDirectoryContents(folderURL.path, contents: [cueFile])
        
        await audiobookManager.importAudiobookFolder(from: folderURL)
        
        #expect(audiobookManager.isImporting == false)
        
        // Should handle gracefully without importing invalid content
        audiobookManager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(300))
        
        // No valid audiobook should be imported
        let validBooks = audiobookManager.audiobooks.filter { $0.fileURL != nil }
        #expect(validBooks.isEmpty)
    }
    
    // MARK: - Rollback and Cleanup Tests
    
    @Test("Failed import workflow properly cleans up partial state")
    func testFailedImportCleanup() async throws {
        let zipURL = createMockZIPFile(named: "FailingImport.zip", containing: [:])
        
        // Simulate extraction failure
        MockFileManager.shouldFailFileOperations = true
        MockFileManager.setFileExists(zipURL.path, exists: true)
        
        await audiobookManager.importZIPAudiobook(from: zipURL)
        
        #expect(audiobookManager.isImporting == false)
        
        // Verify no partial state remains
        audiobookManager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(300))
        
        #expect(audiobookManager.audiobooks.isEmpty)
        #expect(audiobookManager.audiobookNeedingCover == nil)
        
        // Verify Core Data is clean (no orphaned entities)
        let request: NSFetchRequest<Audiobook> = Audiobook.fetchRequest()
        let count = try testContext.count(for: request)
        #expect(count == 0)
    }
    
    // MARK: - Performance Integration Tests
    
    @Test("Large file import workflow completes within reasonable time")
    func testLargeFileImportPerformance() async throws {
        let startTime = Date()
        
        let largeZipURL = createMockZIPFile(
            named: "LargeAudiobook.zip",
            containing: [
                "part1.mp3": 500_000_000, // 500MB
                "part2.mp3": 500_000_000, // 500MB
                "part3.mp3": 500_000_000  // 500MB (1.5GB total)
            ]
        )
        
        MockFileManager.setFileExists(largeZipURL.path, exists: true)
        
        await audiobookManager.importZIPAudiobook(from: largeZipURL)
        
        let importDuration = Date().timeIntervalSince(startTime)
        
        #expect(audiobookManager.isImporting == false)
        #expect(importDuration < 30.0) // Should complete within 30 seconds (mock operation)
        
        // Verify successful import
        audiobookManager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(500))
        
        #expect(audiobookManager.audiobooks.count == 1)
    }
    
    // MARK: - Multi-Format Integration Tests
    
    @Test("Mixed format import workflow handles various audio formats")
    func testMixedFormatImportWorkflow() async throws {
        let folderURL = createMockAudiobookFolder(
            named: "MixedFormats",
            chapters: [
                ("intro.mp3", 600.0),    // MP3
                ("chapter1.m4a", 1800.0), // M4A
                ("chapter2.flac", 2400.0), // FLAC
                ("chapter3.ogg", 1200.0)   // OGG
            ]
        )
        
        MockFileManager.setFileExists(folderURL.path, exists: true)
        
        await audiobookManager.importAudiobookFolder(from: folderURL)
        
        #expect(audiobookManager.isImporting == false)
        
        audiobookManager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(500))
        
        #expect(audiobookManager.audiobooks.count == 1)
        
        let audiobook = audiobookManager.audiobooks.first!
        let chapters = audiobook.chapters?.allObjects as? [Chapter]
        #expect(chapters?.count == 4)
        
        // Test playback engine handles mixed formats
        await globalAudioManager.loadAudiobook(audiobook)
        try await Task.sleep(for: .milliseconds(500))
        
        #expect(globalAudioManager.useMultiFileEngine == true)
        #expect(globalAudioManager.isReady == true)
        
        // Total duration should be sum of all chapters
        let expectedDuration = 600.0 + 1800.0 + 2400.0 + 1200.0
        let actualDuration = globalAudioManager.getDuration()
        #expect(abs(actualDuration - expectedDuration) < 60.0) // Allow some variance
    }
    
    // MARK: - Helper Methods
    
    private func createMockZIPFile(named filename: String, containing files: [String: Int64]) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let zipURL = tempDir.appendingPathComponent(filename)
        
        // Create mock ZIP file with metadata about contained files
        let mockData = Data(count: Int(files.values.reduce(0, +) / 10)) // Compressed size estimate
        try? mockData.write(to: zipURL)
        
        // Store file information for mock extraction
        for (fileName, size) in files {
            MockFileManager.setFileSize(fileName, size: size)
            MockFileManager.setFileExists(fileName, exists: true)
        }
        
        return zipURL
    }
    
    private func createMockAudiobookFolder(
        named folderName: String,
        chapters: [(String, TimeInterval)],
        includeCover: Bool = false
    ) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let folderURL = tempDir.appendingPathComponent(folderName)
        
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        
        var contents: [URL] = []
        
        for (fileName, duration) in chapters {
            let fileURL = folderURL.appendingPathComponent(fileName)
            let fileSize = Int64(duration * 50_000) // Rough estimation: 50KB per second
            let mockData = Data(count: Int(fileSize))
            
            try? mockData.write(to: fileURL)
            MockFileManager.setFileExists(fileURL.path, exists: true)
            MockFileManager.setFileSize(fileURL.path, size: fileSize)
            contents.append(fileURL)
        }
        
        if includeCover {
            let coverURL = folderURL.appendingPathComponent("cover.jpg")
            let coverData = Data(count: 500_000) // 500KB cover
            try? coverData.write(to: coverURL)
            MockFileManager.setFileExists(coverURL.path, exists: true)
            contents.append(coverURL)
        }
        
        MockFileManager.setDirectoryContents(folderURL.path, contents: contents)
        
        return folderURL
    }
    
    private func createTempDirectory(named dirname: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let dirURL = tempDir.appendingPathComponent(dirname)
        
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        
        return dirURL
    }
    
    private func cleanupTempFiles() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let contents = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        
        for url in contents ?? [] {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - Test Tags
extension Tag {
    @Tag static var integration: Self
}