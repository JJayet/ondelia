//
//  PlaybackIntegrationTests.swift
//  AudiobookReaderTests
//
//  Created by AudiobookReader Testing Infrastructure - Phase 2
//

import Testing
import Foundation
import CoreData
import Combine
import AVFoundation
@testable import AudiobookReader

@Suite("Playback Integration Tests", .tags(.integration, .playback))
struct PlaybackIntegrationTests {
    
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
        MockCUEParser.reset()
    }
    
    // MARK: - Single File Playback Workflow Tests
    
    @Test("Complete single file playback workflow: Load → Play → Pause → Resume → Stop")
    func testSingleFilePlaybackWorkflow() async throws {
        // Setup: Create and import single file audiobook
        let audiobook = await createAndImportSingleFileAudiobook(
            title: "Single File Test",
            duration: 3600.0 // 1 hour
        )
        
        // Step 1: Load audiobook into global manager
        await globalAudioManager.loadAudiobook(audiobook)
        try await Task.sleep(for: .milliseconds(500))
        
        #expect(globalAudioManager.currentAudiobook?.objectID == audiobook.objectID)
        #expect(globalAudioManager.useMultiFileEngine == false)
        #expect(globalAudioManager.audioEngine != nil)
        #expect(globalAudioManager.isReady == true)
        #expect(globalAudioManager.playbackState == .paused)
        
        // Step 2: Start playback
        globalAudioManager.startPlayback()
        
        #expect(globalAudioManager.playbackState == .playing)
        #expect(globalAudioManager.isPlaying() == true)
        #expect(globalAudioManager.showMiniPlayer == true)
        
        // Step 3: Verify time progression (mock simulation)
        try await Task.sleep(for: .milliseconds(200))
        let timeAfterPlay = globalAudioManager.getCurrentTime()
        #expect(timeAfterPlay >= 0)
        
        // Step 4: Pause playback
        globalAudioManager.pausePlayback()
        
        #expect(globalAudioManager.playbackState == .paused)
        #expect(globalAudioManager.isPlaying() == false)
        #expect(globalAudioManager.showMiniPlayer == true) // Should remain visible
        
        // Step 5: Resume playback
        globalAudioManager.resumePlayback()
        
        #expect(globalAudioManager.playbackState == .playing)
        #expect(globalAudioManager.isPlaying() == true)
        
        // Step 6: Test seeking functionality
        let seekTime: TimeInterval = 1800.0 // 30 minutes
        globalAudioManager.seek(to: seekTime)
        
        #expect(abs(globalAudioManager.getCurrentTime() - seekTime) < 5.0) // Allow some variance
        
        // Step 7: Stop playback
        globalAudioManager.stopPlayback()
        
        #expect(globalAudioManager.playbackState == .stopped)
        #expect(globalAudioManager.isPlaying() == false)
        #expect(globalAudioManager.showMiniPlayer == false)
    }
    
    @Test("Single file with chapters playback workflow")
    func testSingleFileWithChaptersWorkflow() async throws {
        // Create audiobook with embedded chapters
        let audiobook = await createAndImportSingleFileAudiobook(
            title: "Chaptered Audiobook",
            duration: 7200.0 // 2 hours
        )
        
        // Add chapters manually for testing
        let chapter1 = Chapter(context: testContext)
        chapter1.id = UUID()
        chapter1.title = "Introduction"
        chapter1.startTime = 0.0
        chapter1.endTime = 1800.0 // 30 minutes
        chapter1.chapterNumber = 1
        chapter1.audiobook = audiobook
        
        let chapter2 = Chapter(context: testContext)
        chapter2.id = UUID()
        chapter2.title = "Main Content"
        chapter2.startTime = 1800.0
        chapter2.endTime = 5400.0 // 1.5 hours
        chapter2.chapterNumber = 2
        chapter2.audiobook = audiobook
        
        let chapter3 = Chapter(context: testContext)
        chapter3.id = UUID()
        chapter3.title = "Conclusion"
        chapter3.startTime = 5400.0
        chapter3.endTime = 7200.0 // 30 minutes
        chapter3.chapterNumber = 3
        chapter3.audiobook = audiobook
        
        try testContext.save()
        
        // Load and test chapter navigation
        await globalAudioManager.loadAudiobook(audiobook)
        try await Task.sleep(for: .milliseconds(500))
        
        #expect(globalAudioManager.isReady == true)
        
        // Start playbook from beginning
        globalAudioManager.startPlayback()
        
        // Test chapter seeking
        // Jump to second chapter
        globalAudioManager.seek(to: 1800.0)
        #expect(abs(globalAudioManager.getCurrentTime() - 1800.0) < 5.0)
        
        // Jump to third chapter
        globalAudioManager.seek(to: 5400.0)
        #expect(abs(globalAudioManager.getCurrentTime() - 5400.0) < 5.0)
        
        // Verify seeking within chapter bounds
        globalAudioManager.seek(to: 6000.0) // Middle of third chapter
        #expect(globalAudioManager.getCurrentTime() >= 5400.0) // Should be in third chapter
        #expect(globalAudioManager.getCurrentTime() <= 7200.0)
    }
    
    // MARK: - Multi-File Playback Workflow Tests
    
    @Test("Complete multi-file playbook workflow with chapter transitions")
    func testMultiFilePlaybackWorkflow() async throws {
        // Setup: Create multi-file audiobook
        let audiobook = await createAndImportMultiFileAudiobook(
            title: "Multi-File Audiobook",
            chapters: [
                ("Chapter1.mp3", 1800.0), // 30 minutes
                ("Chapter2.mp3", 2400.0), // 40 minutes
                ("Chapter3.mp3", 1800.0)  // 30 minutes
            ]
        )
        
        // Load audiobook
        await globalAudioManager.loadAudiobook(audiobook)
        try await Task.sleep(for: .milliseconds(500))
        
        #expect(globalAudioManager.useMultiFileEngine == true)
        #expect(globalAudioManager.multiFileAudioEngine != nil)
        #expect(globalAudioManager.audioEngine == nil)
        #expect(globalAudioManager.isReady == true)
        
        let totalDuration = globalAudioManager.getDuration()
        let expectedDuration = 1800.0 + 2400.0 + 1800.0 // 6000 seconds total
        #expect(abs(totalDuration - expectedDuration) < 60.0) // Allow variance
        
        // Start playback from beginning
        globalAudioManager.startPlayback()
        #expect(globalAudioManager.playbackState == .playing)
        
        // Test cross-chapter seeking
        // Seek to middle of second chapter (1800 + 1200 = 3000 seconds)
        let seekTime: TimeInterval = 3000.0
        globalAudioManager.seek(to: seekTime)
        
        let currentTime = globalAudioManager.getCurrentTime()
        #expect(abs(currentTime - seekTime) < 10.0)
        
        // Test seeking to third chapter (beyond 4200 seconds)
        globalAudioManager.seek(to: 5000.0)
        #expect(globalAudioManager.getCurrentTime() >= 4200.0) // Should be in third chapter
        
        // Test skip operations across chapter boundaries
        globalAudioManager.seek(to: 1700.0) // Near end of first chapter
        globalAudioManager.skipForward(200.0) // Should cross into second chapter
        
        let timeAfterSkip = globalAudioManager.getCurrentTime()
        #expect(timeAfterSkip >= 1800.0) // Should be in second chapter now
        #expect(timeAfterSkip <= 1950.0)
    }
    
    @Test("Multi-file playbook handles missing file gracefully")
    func testMultiFileWithMissingFileWorkflow() async throws {
        let audiobook = await createAndImportMultiFileAudiobook(
            title: "Partial Multi-File",
            chapters: [
                ("Available1.mp3", 1800.0),
                ("Missing.mp3", 2400.0),    // This file will be "missing"
                ("Available2.mp3", 1800.0)
            ]
        )
        
        // Simulate missing middle file
        if let chapters = audiobook.chapters?.allObjects as? [Chapter] {
            for chapter in chapters {
                if chapter.title?.contains("Missing") == true {
                    // Remove the file from mock filesystem
                    MockFileManager.setFileExists("Missing.mp3", exists: false)
                }
            }
        }
        
        await globalAudioManager.loadAudiobook(audiobook)
        try await Task.sleep(for: .milliseconds(500))
        
        // Should load successfully but handle missing file
        #expect(globalAudioManager.useMultiFileEngine == true)
        #expect(globalAudioManager.isReady == true || globalAudioManager.playbackState == .failed)
        
        if globalAudioManager.isReady {
            // If loaded successfully, should handle playback around missing file
            globalAudioManager.startPlayback()
            
            // Test seeking past the missing file
            globalAudioManager.seek(to: 4500.0) // Should be in third chapter if missing file is skipped
            
            // Should handle gracefully without crashing
            #expect(globalAudioManager.playbackState != .failed)
        }
    }
    
    // MARK: - CUE-Based Playback Workflow Tests
    
    @Test("CUE-based single file with virtual chapters playback")
    func testCUEBasedPlaybackWorkflow() async throws {
        // Setup: Create CUE-based audiobook (single file with CUE chapters)
        let audiobook = await createAndImportCUEBasedAudiobook(
            title: "CUE Audiobook",
            totalDuration: 5400.0, // 1.5 hours
            cueChapters: [
                ("Prologue", 0.0, 300.0),      // 5 minutes
                ("Chapter 1", 300.0, 1800.0),  // 25 minutes  
                ("Chapter 2", 1800.0, 3600.0), // 30 minutes
                ("Chapter 3", 3600.0, 5100.0), // 25 minutes
                ("Epilogue", 5100.0, 5400.0)   // 5 minutes
            ]
        )
        
        await globalAudioManager.loadAudiobook(audiobook)
        try await Task.sleep(for: .milliseconds(500))
        
        #expect(globalAudioManager.useMultiFileEngine == false) // Single file with CUE
        #expect(globalAudioManager.audioEngine != nil)
        #expect(globalAudioManager.isReady == true)
        
        // Test CUE-based chapter navigation
        globalAudioManager.startPlayback()
        
        // Jump to Chapter 2 (should be at 1800 seconds)
        globalAudioManager.seek(to: 1800.0)
        let timeAtChapter2 = globalAudioManager.getCurrentTime()
        #expect(abs(timeAtChapter2 - 1800.0) < 5.0)
        
        // Jump to Epilogue (should be at 5100 seconds)
        globalAudioManager.seek(to: 5100.0)
        let timeAtEpilogue = globalAudioManager.getCurrentTime()
        #expect(abs(timeAtEpilogue - 5100.0) < 5.0)
        
        // Test playback within chapter boundaries
        globalAudioManager.seek(to: 2500.0) // Middle of Chapter 2
        #expect(globalAudioManager.getCurrentTime() >= 1800.0) // Within Chapter 2 bounds
        #expect(globalAudioManager.getCurrentTime() <= 3600.0)
    }
    
    // MARK: - Playback State Persistence Tests
    
    @Test("Playback position persists across app lifecycle")
    func testPositionPersistenceWorkflow() async throws {
        let audiobook = await createAndImportSingleFileAudiobook(
            title: "Position Test",
            duration: 7200.0
        )
        
        // First session: Play and stop at specific position
        await globalAudioManager.loadAudiobook(audiobook)
        try await Task.sleep(for: .milliseconds(300))
        
        globalAudioManager.startPlayback()
        globalAudioManager.seek(to: 2500.0) // ~42 minutes
        
        let positionBeforeStop = globalAudioManager.getCurrentTime()
        
        // Update progress (simulates what app does during playback)
        audiobookManager.updateProgress(for: audiobook, currentTime: positionBeforeStop)
        
        globalAudioManager.stopPlayback()
        
        // Second session: Reload audiobook (simulates app restart)
        await globalAudioManager.loadAudiobook(audiobook)
        try await Task.sleep(for: .milliseconds(300))
        
        // Position should be restored
        let restoredPosition = globalAudioManager.getCurrentTime()
        #expect(abs(restoredPosition - positionBeforeStop) < 10.0) // Allow small variance
        
        // Verify saved position in Core Data
        #expect(abs(audiobook.currentPosition - positionBeforeStop) < 10.0)
    }
    
    @Test("Playback state survives audiobook switching")
    func testAudiobookSwitchingWorkflow() async throws {
        // Create two audiobooks
        let audiobook1 = await createAndImportSingleFileAudiobook(
            title: "First Book",
            duration: 3600.0
        )
        
        let audiobook2 = await createAndImportSingleFileAudiobook(
            title: "Second Book", 
            duration: 5400.0
        )
        
        // Play first audiobook
        await globalAudioManager.loadAudiobook(audiobook1)
        try await Task.sleep(for: .milliseconds(300))
        
        globalAudioManager.startPlayback()
        globalAudioManager.seek(to: 1200.0) // 20 minutes
        let book1Position = globalAudioManager.getCurrentTime()
        
        // Update progress for first book
        audiobookManager.updateProgress(for: audiobook1, currentTime: book1Position)
        
        // Switch to second audiobook
        await globalAudioManager.loadAudiobook(audiobook2)
        try await Task.sleep(for: .milliseconds(300))
        
        #expect(globalAudioManager.currentAudiobook?.objectID == audiobook2.objectID)
        #expect(globalAudioManager.getCurrentTime() == 0.0) // Should start from beginning
        
        globalAudioManager.startPlayback()
        globalAudioManager.seek(to: 2000.0) // Different position
        let book2Position = globalAudioManager.getCurrentTime()
        
        audiobookManager.updateProgress(for: audiobook2, currentTime: book2Position)
        
        // Switch back to first audiobook
        await globalAudioManager.loadAudiobook(audiobook1)
        try await Task.sleep(for: .milliseconds(300))
        
        // Should restore first book's position
        let restoredBook1Position = globalAudioManager.getCurrentTime()
        #expect(abs(restoredBook1Position - book1Position) < 10.0)
        
        // Verify both positions are saved correctly
        #expect(abs(audiobook1.currentPosition - book1Position) < 10.0)
        #expect(abs(audiobook2.currentPosition - book2Position) < 10.0)
    }
    
    // MARK: - Audio Processing Integration Tests
    
    @Test("Audio processing features work during playback")
    func testAudioProcessingDuringPlayback() async throws {
        let audiobook = await createAndImportSingleFileAudiobook(
            title: "Audio Processing Test",
            duration: 3600.0
        )
        
        await globalAudioManager.loadAudiobook(audiobook)
        try await Task.sleep(for: .milliseconds(300))
        
        globalAudioManager.startPlayback()
        
        // Test playback rate changes
        #expect(globalAudioManager.getPlaybackRate() == 1.0)
        
        globalAudioManager.setPlaybackRate(1.5)
        #expect(globalAudioManager.getPlaybackRate() == 1.5)
        
        globalAudioManager.setPlaybackRate(0.75)
        #expect(globalAudioManager.getPlaybackRate() == 0.75)
        
        // Test audio enhancement features
        globalAudioManager.enableNoiseSuppression(true)
        globalAudioManager.enableSpeechEnhancement(true)
        globalAudioManager.setEqualizer(bassBoost: 1.5, trebleBoost: 1.2)
        
        // Verify playback continues stable
        #expect(globalAudioManager.playbackState == .playing)
        #expect(globalAudioManager.isPlaying() == true)
        
        // Reset playback rate
        globalAudioManager.setPlaybackRate(1.0)
        #expect(globalAudioManager.getPlaybackRate() == 1.0)
    }
    
    // MARK: - Error Recovery Tests
    
    @Test("Playback recovers from audio session interruption")
    func testAudioSessionInterruptionRecovery() async throws {
        let audiobook = await createAndImportSingleFileAudiobook(
            title: "Interruption Test",
            duration: 3600.0
        )
        
        await globalAudioManager.loadAudiobook(audiobook)
        try await Task.sleep(for: .milliseconds(300))
        
        globalAudioManager.startPlayback()
        #expect(globalAudioManager.playbackState == .playing)
        
        let positionBeforeInterruption = globalAudioManager.getCurrentTime()
        
        // Simulate audio session interruption (e.g., phone call)
        MockAVAudioSession.isOtherAudioPlaying = true
        
        // Playback should be paused
        globalAudioManager.pausePlayback()
        #expect(globalAudioManager.playbackState == .paused)
        
        // Simulate interruption end
        MockAVAudioSession.isOtherAudioPlaying = false
        
        // Resume playback
        globalAudioManager.resumePlayback()
        #expect(globalAudioManager.playbackState == .playing)
        
        // Position should be maintained
        let positionAfterRecovery = globalAudioManager.getCurrentTime()
        #expect(abs(positionAfterRecovery - positionBeforeInterruption) < 5.0)
    }
    
    @Test("Playback handles engine failure gracefully")
    func testEngineFailureRecovery() async throws {
        let audiobook = await createAndImportSingleFileAudiobook(
            title: "Engine Failure Test",
            duration: 3600.0
        )
        
        await globalAudioManager.loadAudiobook(audiobook)
        try await Task.sleep(for: .milliseconds(300))
        
        #expect(globalAudioManager.isReady == true)
        
        // Simulate engine failure
        MockAVAudioSession.shouldFailSetup = true
        
        globalAudioManager.startPlayback()
        
        // Should handle failure gracefully
        // Exact behavior depends on implementation, but shouldn't crash
        let finalState = globalAudioManager.playbackState
        #expect(finalState == .playing || finalState == .failed || finalState == .paused)
        
        // Reset mock for cleanup
        MockAVAudioSession.shouldFailSetup = false
    }
    
    // MARK: - Performance Integration Tests
    
    @Test("Large audiobook playback performance")
    func testLargeAudiobookPlaybackPerformance() async throws {
        let startTime = Date()
        
        // Create large multi-file audiobook
        let audiobook = await createAndImportMultiFileAudiobook(
            title: "Large Audiobook",
            chapters: Array(1...20).map { ("Chapter\($0).mp3", 3600.0) } // 20 hours total
        )
        
        let loadStartTime = Date()
        await globalAudioManager.loadAudiobook(audiobook)
        try await Task.sleep(for: .milliseconds(500))
        let loadTime = Date().timeIntervalSince(loadStartTime)
        
        #expect(globalAudioManager.isReady == true)
        #expect(loadTime < 5.0) // Should load within 5 seconds
        
        // Test seeking performance across large audiobook
        let seekStartTime = Date()
        
        // Seek to middle (10 hours in)
        globalAudioManager.seek(to: 36000.0) // 10 hours
        let seekTime1 = Date().timeIntervalSince(seekStartTime)
        
        // Seek to near end (19 hours in)
        globalAudioManager.seek(to: 68400.0) // 19 hours
        let seekTime2 = Date().timeIntervalSince(seekStartTime) - seekTime1
        
        // Each seek should be fast
        #expect(seekTime1 < 1.0)
        #expect(seekTime2 < 1.0)
        
        let totalTime = Date().timeIntervalSince(startTime)
        #expect(totalTime < 10.0) // Total test should complete quickly
    }
    
    // MARK: - Helper Methods
    
    private func createAndImportSingleFileAudiobook(title: String, duration: TimeInterval) async -> Audiobook {
        let audiobook = Audiobook(context: testContext)
        audiobook.id = UUID()
        audiobook.title = title
        audiobook.author = "Test Author"
        audiobook.duration = duration
        audiobook.currentPosition = 0.0
        audiobook.dateAdded = Date()
        audiobook.isFinished = false
        
        // Create temp file
        let tempFile = createTempAudioFile(named: "\(title).m4a")
        audiobook.fileURL = tempFile.path
        
        MockFileManager.setFileExists(tempFile.path, exists: true)
        MockFileManager.setFileSize(tempFile.path, size: Int64(duration * 50_000)) // Rough size estimate
        
        try? testContext.save()
        return audiobook
    }
    
    private func createAndImportMultiFileAudiobook(title: String, chapters: [(String, TimeInterval)]) async -> Audiobook {
        let audiobook = Audiobook(context: testContext)
        audiobook.id = UUID()
        audiobook.title = title
        audiobook.author = "Test Author"
        audiobook.duration = chapters.reduce(0) { $0 + $1.1 }
        audiobook.currentPosition = 0.0
        audiobook.dateAdded = Date()
        audiobook.isFinished = false
        
        // Create temp directory
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
            
            // Create mock file
            let fileURL = tempDir.appendingPathComponent(fileName)
            let mockData = Data(count: Int(duration * 50_000)) // Mock file size
            try? mockData.write(to: fileURL)
            
            MockFileManager.setFileExists(fileURL.path, exists: true)
            MockFileManager.setFileSize(fileURL.path, size: Int64(duration * 50_000))
            
            currentStartTime += duration
        }
        
        MockFileManager.setFileExists(tempDir.path, exists: true)
        
        try? testContext.save()
        return audiobook
    }
    
    private func createAndImportCUEBasedAudiobook(
        title: String,
        totalDuration: TimeInterval,
        cueChapters: [(String, TimeInterval, TimeInterval)]
    ) async -> Audiobook {
        let audiobook = Audiobook(context: testContext)
        audiobook.id = UUID()
        audiobook.title = title
        audiobook.author = "Test Author"
        audiobook.duration = totalDuration
        audiobook.currentPosition = 0.0
        audiobook.dateAdded = Date()
        audiobook.isFinished = false
        
        // Create single audio file
        let tempFile = createTempAudioFile(named: "\(title).flac")
        audiobook.fileURL = tempFile.path
        
        MockFileManager.setFileExists(tempFile.path, exists: true)
        MockFileManager.setFileSize(tempFile.path, size: Int64(totalDuration * 50_000))
        
        // Create CUE-based chapters
        for (index, (chapterTitle, startTime, endTime)) in cueChapters.enumerated() {
            let chapter = Chapter(context: testContext)
            chapter.id = UUID()
            chapter.title = chapterTitle
            chapter.startTime = startTime
            chapter.endTime = endTime
            chapter.chapterNumber = Int16(index + 1)
            chapter.audiobook = audiobook
        }
        
        try? testContext.save()
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
}

// MARK: - Test Tags
extension Tag {
    @Tag static var playback: Self
}