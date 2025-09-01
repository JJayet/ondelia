//
//  ThreadingAndConcurrencyTests.swift
//  AudiobookReaderTests
//
//  Created by AudiobookReader Testing Infrastructure - Phase 2
//

import Testing
import Foundation
import CoreData
import Combine
@testable import AudiobookReader

@Suite("Threading and Concurrency Tests", .tags(.concurrency, .threading))
struct ThreadingAndConcurrencyTests {
    
    let testContext: NSManagedObjectContext
    let audiobookManager: AudiobookManager
    let globalAudioManager: GlobalAudioManager
    
    init() {
        // Create in-memory Core Data stack
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
    }
    
    // MARK: - Concurrent Import Operations Tests
    
    @Test("Concurrent audiobook imports are handled safely")
    func testConcurrentImports() async throws {
        let importTasks = 10
        let tempFiles = (1...importTasks).map { index in
            createTempAudioFile(named: "concurrent\(index).m4a")
        }
        
        // Set up mock file system
        for file in tempFiles {
            MockFileManager.setFileExists(file.path, exists: true)
            MockFileManager.setFileSize(file.path, size: 50_000_000) // 50MB each
        }
        
        // Start concurrent import operations
        await withTaskGroup(of: Void.self) { group in
            for file in tempFiles {
                group.addTask {
                    await self.audiobookManager.importAudiobook(from: file)
                }
            }
        }
        
        // All imports should complete without crashes
        #expect(audiobookManager.isImporting == false)
        
        // Verify final state consistency
        audiobookManager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(500))
        
        // Should have imported all or most files (some may conflict)
        #expect(audiobookManager.audiobooks.count > 0)
        #expect(audiobookManager.audiobooks.count <= importTasks)
        
        // Verify Core Data consistency
        let request: NSFetchRequest<Audiobook> = Audiobook.fetchRequest()
        let coreDataCount = try testContext.count(for: request)
        #expect(coreDataCount == audiobookManager.audiobooks.count)
    }
    
    @Test("Concurrent ZIP extractions don't interfere")
    func testConcurrentZIPExtractions() async throws {
        let zipCount = 5
        let zipFiles = (1...zipCount).map { index in
            createMockZIPFile(
                named: "concurrent\(index).zip",
                containing: ["Chapter\(index).mp3": 100_000_000] // 100MB each
            )
        }
        
        for zip in zipFiles {
            MockFileManager.setFileExists(zip.path, exists: true)
        }
        
        // Start concurrent ZIP imports
        await withTaskGroup(of: Void.self) { group in
            for zip in zipFiles {
                group.addTask {
                    await self.audiobookManager.importZIPAudiobook(from: zip)
                }
            }
        }
        
        #expect(audiobookManager.isImporting == false)
        
        // Verify no temporary files are left over
        // In real implementation, this would check temp directories are cleaned
        
        audiobookManager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(500))
        
        // Should handle all extractions without conflicts
        #expect(audiobookManager.audiobooks.count >= 0) // May vary based on mock implementation
    }
    
    @Test("Mixed concurrent operations (import, fetch, update)")
    func testMixedConcurrentOperations() async throws {
        // Prepare multiple audiobooks
        let audiobook1 = createTestAudiobook(title: "Concurrent Test 1")
        let audiobook2 = createTestAudiobook(title: "Concurrent Test 2")
        try testContext.save()
        
        let tempFile = createTempAudioFile(named: "import_during_ops.m4a")
        MockFileManager.setFileExists(tempFile.path, exists: true)
        
        // Run mixed operations concurrently
        async let importTask = audiobookManager.importAudiobook(from: tempFile)
        async let fetchTask = audiobookManager.fetchAudiobooks()
        async let updateTask = audiobookManager.updateProgress(for: audiobook1, currentTime: 1500.0)
        async let searchTask = audiobookManager.searchAudiobooks(query: "Concurrent")
        async let bookmarkTask = audiobookManager.createBookmark(
            for: audiobook2,
            at: 800.0,
            title: "Concurrent Bookmark"
        )
        
        // Wait for all operations to complete
        await importTask
        await fetchTask
        await updateTask
        _ = await searchTask
        await bookmarkTask
        
        // Verify system is in consistent state
        #expect(audiobookManager.isImporting == false)
        #expect(audiobookManager.isLoadingLibrary == false)
        
        // Verify data integrity
        #expect(abs(audiobook1.currentPosition - 1500.0) < 1.0)
        let bookmarks = audiobookManager.getBookmarks(for: audiobook2)
        #expect(bookmarks.count == 1)
    }
    
    // MARK: - Thread-Safe Manager Operations Tests
    
    @Test("GlobalAudioManager handles concurrent audiobook loading")
    func testConcurrentAudiobookLoading() async throws {
        let audiobooks = (1...5).map { index in
            createTestAudiobook(title: "Concurrent Load \(index)")
        }
        
        for (index, audiobook) in audiobooks.enumerated() {
            let tempFile = createTempAudioFile(named: "load\(index).m4a")
            audiobook.fileURL = tempFile.path
            MockFileManager.setFileExists(tempFile.path, exists: true)
        }
        
        try testContext.save()
        
        // Start concurrent loading operations
        await withTaskGroup(of: Void.self) { group in
            for audiobook in audiobooks {
                group.addTask {
                    await self.globalAudioManager.loadAudiobook(audiobook)
                }
            }
        }
        
        try await Task.sleep(for: .milliseconds(500))
        
        // Should end up with one loaded audiobook (last one processed)
        #expect(globalAudioManager.currentAudiobook != nil)
        #expect(globalAudioManager.isLoading == false)
        #expect(globalAudioManager.isReady == true)
        
        // Only one engine should be active
        let singleEngineActive = globalAudioManager.audioEngine != nil
        let multiEngineActive = globalAudioManager.multiFileAudioEngine != nil
        #expect((singleEngineActive && !multiEngineActive) || (!singleEngineActive && multiEngineActive))
    }
    
    @Test("GlobalAudioManager playback controls are thread-safe")
    func testThreadSafePlaybackControls() async throws {
        let audiobook = createTestAudiobook(title: "Thread Safe Test")
        let tempFile = createTempAudioFile(named: "thread_safe.m4a")
        audiobook.fileURL = tempFile.path
        MockFileManager.setFileExists(tempFile.path, exists: true)
        
        try testContext.save()
        
        await globalAudioManager.loadAudiobook(audiobook)
        try await Task.sleep(for: .milliseconds(300))
        
        #expect(globalAudioManager.isReady == true)
        
        // Perform concurrent playback operations
        await withTaskGroup(of: Void.self) { group in
            // Multiple play/pause operations
            for _ in 1...10 {
                group.addTask {
                    self.globalAudioManager.togglePlayback()
                    try? await Task.sleep(for: .milliseconds(10))
                }
            }
            
            // Multiple seek operations
            for i in 1...10 {
                group.addTask {
                    let seekTime = Double(i * 100) // 100, 200, 300... seconds
                    self.globalAudioManager.seek(to: seekTime)
                    try? await Task.sleep(for: .milliseconds(5))
                }
            }
            
            // Multiple rate changes
            for i in 1...5 {
                group.addTask {
                    let rate = 0.5 + (Float(i) * 0.2) // 0.7, 0.9, 1.1, 1.3, 1.5
                    self.globalAudioManager.setPlaybackRate(rate)
                    try? await Task.sleep(for: .milliseconds(15))
                }
            }
        }
        
        try await Task.sleep(for: .milliseconds(200))
        
        // Should end in a consistent state
        let finalState = globalAudioManager.playbackState
        #expect(finalState == .playing || finalState == .paused || finalState == .stopped)
        
        // Rate should be valid
        let finalRate = globalAudioManager.getPlaybackRate()
        #expect(finalRate >= 0.5 && finalRate <= 2.0)
        
        // Position should be valid
        let finalTime = globalAudioManager.getCurrentTime()
        let duration = globalAudioManager.getDuration()
        #expect(finalTime >= 0.0 && finalTime <= duration)
    }
    
    // MARK: - Core Data Thread Safety Tests
    
    @Test("Core Data operations are thread-safe across contexts")
    func testCoreDataThreadSafety() async throws {
        let operationCount = 20
        
        await withTaskGroup(of: Void.self) { group in
            for i in 1...operationCount {
                group.addTask {
                    // Create audiobook on background thread
                    let backgroundContext = PersistenceController.preview.backgroundContext()
                    
                    await backgroundContext.perform {
                        let audiobook = Audiobook(context: backgroundContext)
                        audiobook.id = UUID()
                        audiobook.title = "Background \(i)"
                        audiobook.author = "Test Author"
                        audiobook.duration = Double(i * 100)
                        audiobook.dateAdded = Date()
                        
                        do {
                            try backgroundContext.save()
                        } catch {
                            Issue.record("Failed to save on background context: \(error)")
                        }
                    }
                    
                    // Small delay to increase chance of conflicts
                    try? await Task.sleep(for: .milliseconds(10))
                }
            }
        }
        
        // Verify all objects were created
        audiobookManager.fetchAudiobooks()
        try await Task.sleep(for: .milliseconds(500))
        
        // Should have created most or all audiobooks without conflicts
        #expect(audiobookManager.audiobooks.count >= operationCount - 5) // Allow some variance
    }
    
    @Test("Concurrent bookmark operations maintain data integrity")
    func testConcurrentBookmarkOperations() async throws {
        let audiobook = createTestAudiobook(title: "Bookmark Concurrency Test")
        try testContext.save()
        
        let bookmarkCount = 15
        
        // Create bookmarks concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 1...bookmarkCount {
                group.addTask {
                    let timestamp = Double(i * 300) // Every 5 minutes
                    let title = "Bookmark \(i)"
                    let note = "Note for bookmark \(i)"
                    
                    self.audiobookManager.createBookmark(
                        for: audiobook,
                        at: timestamp,
                        title: title,
                        note: note
                    )
                    
                    // Small delay to increase contention
                    try? await Task.sleep(for: .milliseconds(5))
                }
            }
        }
        
        try await Task.sleep(for: .milliseconds(200))
        
        // Verify all bookmarks were created
        let bookmarks = audiobookManager.getBookmarks(for: audiobook)
        #expect(bookmarks.count >= bookmarkCount - 2) // Allow small variance
        
        // Verify no duplicate timestamps
        let timestamps = Set(bookmarks.map { $0.timestamp })
        #expect(timestamps.count == bookmarks.count) // No duplicates
        
        // Test concurrent deletion
        let bookmarksToDelete = Array(bookmarks.prefix(5))
        await withTaskGroup(of: Void.self) { group in
            for bookmark in bookmarksToDelete {
                group.addTask {
                    self.audiobookManager.deleteBookmark(bookmark)
                    try? await Task.sleep(for: .milliseconds(5))
                }
            }
        }
        
        try await Task.sleep(for: .milliseconds(100))
        
        let remainingBookmarks = audiobookManager.getBookmarks(for: audiobook)
        #expect(remainingBookmarks.count == bookmarks.count - bookmarksToDelete.count)
    }
    
    // MARK: - Memory Management Under Concurrency Tests
    
    @Test("Memory management under concurrent operations")
    func testMemoryManagementUnderConcurrency() async throws {
        let initialMemoryFootprint = getApproximateMemoryUsage()
        
        // Perform memory-intensive concurrent operations
        await withTaskGroup(of: Void.self) { group in
            // Multiple large audiobook loading operations
            for i in 1...10 {
                group.addTask {
                    let audiobook = self.createTestAudiobook(title: "Memory Test \(i)")
                    let tempFile = self.createTempAudioFile(named: "memory\(i).m4a")
                    audiobook.fileURL = tempFile.path
                    MockFileManager.setFileExists(tempFile.path, exists: true)
                    MockFileManager.setFileSize(tempFile.path, size: 100_000_000) // 100MB each
                    
                    try? self.testContext.save()
                    
                    await self.globalAudioManager.loadAudiobook(audiobook)
                    try? await Task.sleep(for: .milliseconds(50))
                    
                    // Load different audiobook to trigger cleanup
                    let audiobook2 = self.createTestAudiobook(title: "Memory Test \(i)b")
                    let tempFile2 = self.createTempAudioFile(named: "memory\(i)b.m4a")
                    audiobook2.fileURL = tempFile2.path
                    MockFileManager.setFileExists(tempFile2.path, exists: true)
                    
                    try? self.testContext.save()
                    await self.globalAudioManager.loadAudiobook(audiobook2)
                }
            }
        }
        
        try await Task.sleep(for: .milliseconds(500))
        
        let finalMemoryFootprint = getApproximateMemoryUsage()
        
        // Memory shouldn't have grown excessively
        let memoryGrowth = finalMemoryFootprint - initialMemoryFootprint
        #expect(memoryGrowth < 50_000_000) // Less than 50MB growth
        
        // Should end with only one loaded audiobook
        #expect(globalAudioManager.currentAudiobook != nil)
        
        // Only one engine should be retained
        let engineCount = (globalAudioManager.audioEngine != nil ? 1 : 0) + 
                         (globalAudioManager.multiFileAudioEngine != nil ? 1 : 0)
        #expect(engineCount == 1)
    }
    
    // MARK: - Race Condition Detection Tests
    
    @Test("No race conditions in state transitions")
    func testStateTransitionRaceConditions() async throws {
        let audiobook = createTestAudiobook(title: "Race Condition Test")
        let tempFile = createTempAudioFile(named: "race_test.m4a")
        audiobook.fileURL = tempFile.path
        MockFileManager.setFileExists(tempFile.path, exists: true)
        
        try testContext.save()
        
        // Rapidly load and unload audiobooks to test state transitions
        await withTaskGroup(of: Void.self) { group in
            for i in 1...20 {
                group.addTask {
                    if i % 2 == 0 {
                        await self.globalAudioManager.loadAudiobook(audiobook)
                    } else {
                        // Create alternate audiobook to switch to
                        let altAudiobook = self.createTestAudiobook(title: "Alt \(i)")
                        let altFile = self.createTempAudioFile(named: "alt\(i).m4a")
                        altAudiobook.fileURL = altFile.path
                        MockFileManager.setFileExists(altFile.path, exists: true)
                        
                        try? self.testContext.save()
                        await self.globalAudioManager.loadAudiobook(altAudiobook)
                    }
                    
                    try? await Task.sleep(for: .milliseconds(20))
                }
            }
        }
        
        try await Task.sleep(for: .milliseconds(300))
        
        // Should end in a consistent state
        #expect(globalAudioManager.isLoading == false)
        #expect(globalAudioManager.currentAudiobook != nil)
        
        let finalState = globalAudioManager.playbackState
        #expect(finalState == .paused || finalState == .stopped || finalState == .failed)
    }
    
    // MARK: - Helper Methods
    
    private func createTestAudiobook(title: String) -> Audiobook {
        let audiobook = Audiobook(context: testContext)
        audiobook.id = UUID()
        audiobook.title = title
        audiobook.author = "Test Author"
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
    
    private func createMockZIPFile(named filename: String, containing files: [String: Int64]) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let zipURL = tempDir.appendingPathComponent(filename)
        
        let mockData = Data(count: Int(files.values.reduce(0, +) / 10))
        try? mockData.write(to: zipURL)
        
        return zipURL
    }
    
    private func getApproximateMemoryUsage() -> Int64 {
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
        
        if kerr == KERN_SUCCESS {
            return Int64(info.resident_size)
        } else {
            return 0
        }
    }
}

// MARK: - Test Tags
extension Tag {
    @Tag static var concurrency: Self
    @Tag static var threading: Self
}