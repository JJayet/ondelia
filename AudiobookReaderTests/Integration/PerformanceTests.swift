//
//  PerformanceTests.swift
//  AudiobookReaderTests
//
//  Created by AudiobookReader Testing Infrastructure - Phase 2
//

import Testing
import Foundation
import CoreData
import Combine
@testable import AudiobookReader

@Suite("Performance Tests", .tags(.performance))
struct PerformanceTests {
    
    let testContext: NSManagedObjectContext
    let audiobookManager: AudiobookManager
    let globalAudioManager: GlobalAudioManager
    
    init() {
        // Create in-memory Core Data stack for performance testing
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
        
        // Reset all mocks for consistent performance testing
        MockFileManager.reset()
        MockAVAudioSession.reset()
    }
    
    // MARK: - Large File Import Performance Tests
    
    @Test("Large M4B file import performance", .timeLimit(.minutes(1)))
    func testLargeM4BImportPerformance() async throws {
        let startTime = Date()
        
        // Create large audiobook file (1GB simulated)
        let largeFileURL = createTempAudioFile(named: "large_audiobook.m4b")
        MockFileManager.setFileExists(largeFileURL.path, exists: true)
        MockFileManager.setFileSize(largeFileURL.path, size: 1_000_000_000) // 1GB
        
        // Measure import time
        let importStartTime = Date()
        await audiobookManager.importAudiobook(from: largeFileURL)
        let importDuration = Date().timeIntervalSince(importStartTime)
        
        #expect(audiobookManager.isImporting == false)
        #expect(importDuration < 5.0) // Should complete within 5 seconds
        
        // Verify successful import
        audiobookManager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(300))
        
        #expect(audiobookManager.audiobooks.count == 1)
        
        let totalDuration = Date().timeIntervalSince(startTime)
        #expect(totalDuration < 8.0) // Total operation under 8 seconds
    }
    
    @Test("Large ZIP extraction performance", .timeLimit(.minutes(1)))
    func testLargeZIPExtractionPerformance() async throws {
        let startTime = Date()
        
        // Create large ZIP with multiple files (2GB total simulated)
        let largeZipURL = createMockZIPFile(
            named: "large_audiobook.zip",
            containing: [
                "Part1.mp3": 500_000_000,  // 500MB
                "Part2.mp3": 500_000_000,  // 500MB  
                "Part3.mp3": 500_000_000,  // 500MB
                "Part4.mp3": 500_000_000,  // 500MB
                "cover.jpg": 2_000_000     // 2MB
            ]
        )
        
        MockFileManager.setFileExists(largeZipURL.path, exists: true)
        
        let extractionStartTime = Date()
        await audiobookManager.importZIPAudiobook(from: largeZipURL)
        let extractionDuration = Date().timeIntervalSince(extractionStartTime)
        
        #expect(audiobookManager.isImporting == false)
        #expect(extractionDuration < 10.0) // Should extract within 10 seconds
        
        let totalDuration = Date().timeIntervalSince(startTime)
        #expect(totalDuration < 12.0) // Total operation under 12 seconds
    }
    
    @Test("Multi-file folder import performance", .timeLimit(.minutes(1)))
    func testMultiFileFolderImportPerformance() async throws {
        // Create folder with many files (50 chapters)
        let chapters = (1...50).map { index in
            ("Chapter\(String(format: "%02d", index)).mp3", Double(index * 60 * 15)) // 15 min each
        }
        
        let folderURL = createMockAudiobookFolder(
            named: "LargeMultiFileAudiobook",
            chapters: chapters,
            includeCover: true
        )
        
        MockFileManager.setFileExists(folderURL.path, exists: true)
        
        let importStartTime = Date()
        await audiobookManager.importAudiobookFolder(from: folderURL)
        let importDuration = Date().timeIntervalSince(importStartTime)
        
        #expect(audiobookManager.isImporting == false)
        #expect(importDuration < 6.0) // Should handle 50 files within 6 seconds
        
        // Verify all chapters are imported
        audiobookManager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(300))
        
        if let audiobook = audiobookManager.audiobooks.first {
            #expect(audiobook.chapters?.count == 50)
            
            // Total duration should be correct
            let expectedDuration = Double(chapters.count * 15 * 60) // 50 * 15 minutes
            #expect(abs(audiobook.duration - expectedDuration) < 60.0)
        }
    }
    
    // MARK: - Audio Engine Performance Tests
    
    @Test("Audio engine initialization performance", .timeLimit(.minutes(1)))
    func testAudioEngineInitializationPerformance() async throws {
        let audiobook = createTestAudiobook(title: "Engine Init Test")
        let tempFile = createTempAudioFile(named: "engine_init.m4a")
        audiobook.fileURL = tempFile.path
        audiobook.duration = 14400.0 // 4 hours
        
        MockFileManager.setFileExists(tempFile.path, exists: true)
        MockFileManager.setFileSize(tempFile.path, size: 200_000_000) // 200MB
        
        try testContext.save()
        
        let initStartTime = Date()
        await globalAudioManager.loadAudiobook(audiobook)
        try await Task.sleep(for: .milliseconds(100)) // Allow for async initialization
        
        let initDuration = Date().timeIntervalSince(initStartTime)
        
        #expect(globalAudioManager.isReady == true)
        #expect(globalAudioManager.audioEngine != nil)
        #expect(initDuration < 2.0) // Should initialize within 2 seconds
        
        // Test immediate playback readiness
        let playStartTime = Date()
        globalAudioManager.startPlayback()
        let playDuration = Date().timeIntervalSince(playStartTime)
        
        #expect(globalAudioManager.isPlaying() == true)
        #expect(playDuration < 0.5) // Should start playing within 500ms
    }
    
    @Test("Multi-file engine initialization performance", .timeLimit(.minutes(1)))
    func testMultiFileEngineInitializationPerformance() async throws {
        // Create audiobook with many chapters
        let audiobook = createTestAudiobook(title: "Multi-File Engine Test")
        let tempDir = createTempDirectory(named: "MultiFileEngineTest")
        audiobook.fileURL = tempDir.path
        
        var totalDuration: TimeInterval = 0
        
        // Create 30 chapters
        for i in 1...30 {
            let chapter = Chapter(context: testContext)
            chapter.id = UUID()
            chapter.title = "Chapter \(i)"
            chapter.startTime = totalDuration
            chapter.endTime = totalDuration + 1800.0 // 30 minutes each
            chapter.chapterNumber = Int16(i)
            chapter.audiobook = audiobook
            
            let chapterFile = tempDir.appendingPathComponent("Chapter\(i).mp3")
            try Data(count: 50_000_000).write(to: chapterFile) // 50MB per file
            MockFileManager.setFileExists(chapterFile.path, exists: true)
            
            totalDuration += 1800.0
        }
        
        audiobook.duration = totalDuration
        MockFileManager.setFileExists(tempDir.path, exists: true)
        
        try testContext.save()
        
        let initStartTime = Date()
        await globalAudioManager.loadAudiobook(audiobook)
        try await Task.sleep(for: .milliseconds(200))
        
        let initDuration = Date().timeIntervalSince(initStartTime)
        
        #expect(globalAudioManager.useMultiFileEngine == true)
        #expect(globalAudioManager.multiFileAudioEngine != nil)
        #expect(globalAudioManager.isReady == true)
        #expect(initDuration < 3.0) // Should handle 30 files within 3 seconds
    }
    
    // MARK: - Seeking Performance Tests
    
    @Test("Large file seeking performance", .timeLimit(.minutes(1)))
    func testLargeFileSeekingPerformance() async throws {
        let audiobook = createTestAudiobook(title: "Seeking Test")
        let tempFile = createTempAudioFile(named: "large_seek.m4a")
        audiobook.fileURL = tempFile.path
        audiobook.duration = 43200.0 // 12 hours
        
        MockFileManager.setFileExists(tempFile.path, exists: true)
        MockFileManager.setFileSize(tempFile.path, size: 600_000_000) // 600MB
        
        try testContext.save()
        
        await globalAudioManager.loadAudiobook(audiobook)
        try await Task.sleep(for: .milliseconds(200))
        
        #expect(globalAudioManager.isReady == true)
        
        // Test multiple seek operations
        let seekPositions: [TimeInterval] = [
            3600.0,   // 1 hour
            18000.0,  // 5 hours
            36000.0,  // 10 hours
            7200.0,   // 2 hours (backwards)
            25200.0,  // 7 hours
            1800.0    // 30 minutes (far backwards)
        ]
        
        let totalSeekStartTime = Date()
        
        for position in seekPositions {
            let seekStartTime = Date()
            globalAudioManager.seek(to: position)
            let seekDuration = Date().timeIntervalSince(seekStartTime)
            
            #expect(seekDuration < 0.2) // Each seek under 200ms
            #expect(abs(globalAudioManager.getCurrentTime() - position) < 5.0)
        }
        
        let totalSeekDuration = Date().timeIntervalSince(totalSeekStartTime)
        #expect(totalSeekDuration < 1.0) // All seeks within 1 second
    }
    
    @Test("Multi-file cross-chapter seeking performance", .timeLimit(.minutes(1)))
    func testMultiFileCrossChapterSeekingPerformance() async throws {
        let chapters = (1...20).map { index in
            ("Chapter\(index).mp3", 1800.0) // 30 minutes each
        }
        
        let audiobook = await createMultiFileAudiobook(
            title: "Cross Chapter Seek Test",
            chapters: chapters
        )
        
        await globalAudioManager.loadAudiobook(audiobook)
        try await Task.sleep(for: .milliseconds(300))
        
        #expect(globalAudioManager.useMultiFileEngine == true)
        #expect(globalAudioManager.isReady == true)
        
        // Test cross-chapter seeks
        let crossSeekPositions: [TimeInterval] = [
            0.0,      // Chapter 1
            1800.0,   // Chapter 2
            7200.0,   // Chapter 5  
            18000.0,  // Chapter 11
            32400.0,  // Chapter 19
            5400.0,   // Back to Chapter 4
            36000.0   // Final chapter
        ]
        
        let crossSeekStartTime = Date()
        
        for position in crossSeekPositions {
            let seekStartTime = Date()
            globalAudioManager.seek(to: position)
            let seekDuration = Date().timeIntervalSince(seekStartTime)
            
            #expect(seekDuration < 0.3) // Cross-chapter seek under 300ms
            #expect(abs(globalAudioManager.getCurrentTime() - position) < 10.0)
        }
        
        let totalCrossSeekDuration = Date().timeIntervalSince(crossSeekStartTime)
        #expect(totalCrossSeekDuration < 2.0) // All cross-seeks within 2 seconds
    }
    
    // MARK: - Core Data Performance Tests
    
    @Test("Large library fetch performance", .timeLimit(.minutes(1)))
    func testLargeLibraryFetchPerformance() async throws {
        // Create large library (500 audiobooks)
        for i in 1...500 {
            let audiobook = createTestAudiobook(title: "Audiobook \(i)")
            let tempFile = createTempAudioFile(named: "book\(i).m4a")
            audiobook.fileURL = tempFile.path
            audiobook.author = "Author \(i % 50)" // 10 books per author
            audiobook.duration = Double(i * 100) // Varying durations
            
            MockFileManager.setFileExists(tempFile.path, exists: true)
            
            // Add some chapters for every 10th book
            if i % 10 == 0 {
                for j in 1...5 {
                    let chapter = Chapter(context: testContext)
                    chapter.id = UUID()
                    chapter.title = "Chapter \(j)"
                    chapter.startTime = Double((j - 1) * 600)
                    chapter.endTime = Double(j * 600)
                    chapter.chapterNumber = Int16(j)
                    chapter.audiobook = audiobook
                }
            }
        }
        
        try testContext.save()
        
        // Measure fetch performance
        let fetchStartTime = Date()
        audiobookManager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(500)) // Allow background fetch
        let fetchDuration = Date().timeIntervalSince(fetchStartTime)
        
        #expect(audiobookManager.isLoadingLibrary == false)
        #expect(audiobookManager.audiobooks.count == 500)
        #expect(fetchDuration < 2.0) // Should fetch 500 books within 2 seconds
    }
    
    @Test("Search performance on large library", .timeLimit(.minutes(1)))
    func testSearchPerformanceOnLargeLibrary() async throws {
        // Create diverse library for searching
        let authors = ["Asimov", "Clarke", "Heinlein", "Herbert", "Dick"]
        let genres = ["Sci-Fi", "Fantasy", "Mystery", "Thriller", "Biography"]
        
        for i in 1...200 {
            let audiobook = createTestAudiobook(
                title: "\(genres[i % 5]) Book \(i)",
                author: authors[i % 5]
            )
            let tempFile = createTempAudioFile(named: "search\(i).m4a")
            audiobook.fileURL = tempFile.path
            MockFileManager.setFileExists(tempFile.path, exists: true)
        }
        
        try testContext.save()
        
        // Load library first
        audiobookManager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(300))
        
        #expect(audiobookManager.audiobooks.count == 200)
        
        // Test various search scenarios
        let searchQueries = ["Asimov", "Sci-Fi", "Book 1", "Fantasy", "Mystery"]
        
        for query in searchQueries {
            let searchStartTime = Date()
            let results = audiobookManager.searchAudiobooks(query: query)
            let searchDuration = Date().timeIntervalSince(searchStartTime)
            
            #expect(searchDuration < 0.1) // Search should be under 100ms
            #expect(results.count > 0) // Should find matches
        }
    }
    
    // MARK: - Memory Usage Performance Tests
    
    @Test("Memory usage during large operations", .timeLimit(.minutes(1)))
    func testMemoryUsageDuringLargeOperations() async throws {
        let initialMemory = getMemoryUsage()
        
        // Perform memory-intensive operations
        
        // 1. Import multiple large files
        for i in 1...5 {
            let largeFileURL = createTempAudioFile(named: "memory_test_\(i).m4b")
            MockFileManager.setFileExists(largeFileURL.path, exists: true)
            MockFileManager.setFileSize(largeFileURL.path, size: 500_000_000) // 500MB each
            
            await audiobookManager.importAudiobook(from: largeFileURL)
        }
        
        let postImportMemory = getMemoryUsage()
        
        // 2. Load and switch between audiobooks rapidly
        audiobookManager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(300))
        
        for audiobook in audiobookManager.audiobooks {
            await globalAudioManager.loadAudiobook(audiobook)
            try await Task.sleep(for: .milliseconds(100))
        }
        
        let postLoadingMemory = getMemoryUsage()
        
        // 3. Perform intensive seeking
        if let lastAudiobook = audiobookManager.audiobooks.last {
            await globalAudioManager.loadAudiobook(lastAudiobook)
            try await Task.sleep(for: .milliseconds(200))
            
            for _ in 1...50 {
                let randomPosition = Double.random(in: 0...lastAudiobook.duration)
                globalAudioManager.seek(to: randomPosition)
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        
        let finalMemory = getMemoryUsage()
        
        // Memory growth should be reasonable
        let totalGrowth = finalMemory - initialMemory
        let importGrowth = postImportMemory - initialMemory
        let loadingGrowth = postLoadingMemory - postImportMemory
        
        #expect(totalGrowth < 100_000_000) // Total growth under 100MB
        #expect(importGrowth < 80_000_000)  // Import growth under 80MB
        #expect(loadingGrowth < 20_000_000) // Loading growth under 20MB
        
        // Should have reasonable final memory footprint
        #expect(finalMemory < initialMemory + 150_000_000) // Under 150MB total growth
    }
    
    // MARK: - Batch Operations Performance Tests
    
    @Test("Batch bookmark operations performance", .timeLimit(.minutes(1)))
    func testBatchBookmarkOperationsPerformance() async throws {
        let audiobook = createTestAudiobook(title: "Batch Bookmark Test")
        audiobook.duration = 36000.0 // 10 hours
        try testContext.save()
        
        // Create many bookmarks quickly
        let bookmarkCount = 100
        let batchStartTime = Date()
        
        for i in 1...bookmarkCount {
            let timestamp = Double(i * 360) // Every 6 minutes
            audiobookManager.createBookmark(
                for: audiobook,
                at: timestamp,
                title: "Bookmark \(i)",
                note: "Note for bookmark \(i)"
            )
        }
        
        let batchDuration = Date().timeIntervalSince(batchStartTime)
        
        #expect(batchDuration < 1.0) // 100 bookmarks created within 1 second
        
        // Verify all bookmarks created
        let bookmarks = audiobookManager.getBookmarks(for: audiobook)
        #expect(bookmarks.count == bookmarkCount)
        
        // Test batch deletion performance
        let deletionStartTime = Date()
        
        let bookmarksToDelete = Array(bookmarks.prefix(50))
        for bookmark in bookmarksToDelete {
            audiobookManager.deleteBookmark(bookmark)
        }
        
        let deletionDuration = Date().timeIntervalSince(deletionStartTime)
        
        #expect(deletionDuration < 0.5) // 50 deletions within 500ms
        
        // Verify correct number remaining
        let remainingBookmarks = audiobookManager.getBookmarks(for: audiobook)
        #expect(remainingBookmarks.count == bookmarkCount - bookmarksToDelete.count)
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
        
        FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)
        
        return fileURL
    }
    
    private func createTempDirectory(named dirname: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let dirURL = tempDir.appendingPathComponent(dirname)
        
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        
        return dirURL
    }
    
    private func createMockZIPFile(named filename: String, containing files: [String: Int64]) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let zipURL = tempDir.appendingPathComponent(filename)
        
        let totalSize = files.values.reduce(0, +)
        let mockData = Data(count: Int(totalSize / 10)) // Simulated compressed size
        try? mockData.write(to: zipURL)
        
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
            let fileSize = Int64(duration * 50_000) // 50KB per second estimate
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
    
    private func createMultiFileAudiobook(title: String, chapters: [(String, TimeInterval)]) async -> Audiobook {
        let audiobook = Audiobook(context: testContext)
        audiobook.id = UUID()
        audiobook.title = title
        audiobook.author = "Performance Test Author"
        audiobook.duration = chapters.reduce(0) { $0 + $1.1 }
        audiobook.currentPosition = 0.0
        audiobook.dateAdded = Date()
        audiobook.isFinished = false
        
        let tempDir = createTempDirectory(named: title)
        audiobook.fileURL = tempDir.path
        
        var currentStartTime: TimeInterval = 0
        
        for (index, (fileName, duration)) in chapters.enumerated() {
            let chapter = Chapter(context: testContext)
            chapter.id = UUID()
            chapter.title = fileName.replacingOccurrences(of: ".mp3", with: "")
            chapter.startTime = currentStartTime
            chapter.endTime = currentStartTime + duration
            chapter.chapterNumber = Int16(index + 1)
            chapter.audiobook = audiobook
            
            let fileURL = tempDir.appendingPathComponent(fileName)
            let mockData = Data(count: Int(duration * 50_000))
            try? mockData.write(to: fileURL)
            
            MockFileManager.setFileExists(fileURL.path, exists: true)
            MockFileManager.setFileSize(fileURL.path, size: Int64(duration * 50_000))
            
            currentStartTime += duration
        }
        
        MockFileManager.setFileExists(tempDir.path, exists: true)
        
        try? testContext.save()
        return audiobook
    }
    
    private func getMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        return kerr == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
}

// MARK: - Test Tags
extension Tag {
    @Tag static var performance: Self
}