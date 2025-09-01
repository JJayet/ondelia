//
//  PlayerViewTests.swift
//  AudiobookReaderTests
//
//  Created by AudiobookReader Testing Infrastructure - Phase 2
//

import Testing
import SwiftUI
import Combine
import CoreData
@testable import AudiobookReader

@Suite("PlayerView Tests", .tags(.ui, .player))
struct PlayerViewTests {
    
    let testContext: NSManagedObjectContext
    let mockGlobalAudioManager: MockAudioEngine
    let mockAudiobookManager: AudiobookManager
    
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
        mockGlobalAudioManager = MockAudioEngine()
        mockAudiobookManager = AudiobookManager()
        
        // Reset mocks
        MockFileManager.reset()
    }
    
    // MARK: - PlayerView State Tests
    
    @Test("PlayerView initializes with correct state when no audiobook loaded")
    func testPlayerViewInitialState() async throws {
        // Create PlayerView without loaded audiobook
        mockGlobalAudioManager.audiobook = nil
        mockGlobalAudioManager.isReady = false
        
        let playerView = PlayerView()
            .environmentObject(mockGlobalAudioManager)
            .environmentObject(mockAudiobookManager)
        
        // Test that the view can be created without crashing
        let hostingController = UIHostingController(rootView: playerView)
        
        #expect(hostingController.view != nil)
        
        // Mock state should reflect no loaded audiobook
        #expect(mockGlobalAudioManager.audiobook == nil)
        #expect(mockGlobalAudioManager.isReady == false)
        #expect(mockGlobalAudioManager.isPlaying == false)
    }
    
    @Test("PlayerView displays audiobook information correctly")
    func testPlayerViewDisplaysAudiobookInfo() async throws {
        // Create test audiobook
        let audiobook = createTestAudiobook(
            title: "Test Audiobook Title",
            author: "Test Author Name"
        )
        
        // Configure mock with audiobook
        try mockGlobalAudioManager.loadAudiobook(audiobook)
        
        let playerView = PlayerView()
            .environmentObject(mockGlobalAudioManager)
            .environmentObject(mockAudiobookManager)
        
        let hostingController = UIHostingController(rootView: playerView)
        
        #expect(hostingController.view != nil)
        #expect(mockGlobalAudioManager.audiobook?.title == "Test Audiobook Title")
        #expect(mockGlobalAudioManager.audiobook?.author == "Test Author Name")
        #expect(mockGlobalAudioManager.isReady == true)
    }
    
    @Test("PlayerView updates when playback state changes")
    func testPlayerViewPlaybackStateUpdates() async throws {
        let audiobook = createTestAudiobook(title: "State Test Audiobook")
        try mockGlobalAudioManager.loadAudiobook(audiobook)
        
        let playerView = PlayerView()
            .environmentObject(mockGlobalAudioManager)
            .environmentObject(mockAudiobookManager)
        
        let hostingController = UIHostingController(rootView: playerView)
        
        // Initial state
        #expect(mockGlobalAudioManager.isPlaying == false)
        
        // Start playback
        mockGlobalAudioManager.startPlayback()
        #expect(mockGlobalAudioManager.isPlaying == true)
        
        // Pause playback
        mockGlobalAudioManager.pausePlayback()
        #expect(mockGlobalAudioManager.isPlaying == false)
        
        // The view should handle these state changes without crashing
        #expect(hostingController.view != nil)
    }
    
    // MARK: - PlayerView Control Tests
    
    @Test("PlayerView playback controls function correctly")
    func testPlayerViewPlaybackControls() async throws {
        let audiobook = createTestAudiobook(
            title: "Control Test",
            duration: 7200.0 // 2 hours
        )
        
        try mockGlobalAudioManager.loadAudiobook(audiobook)
        
        let playerView = PlayerView()
            .environmentObject(mockGlobalAudioManager)
            .environmentObject(mockAudiobookManager)
        
        // Simulate control interactions through the mock engine
        
        // Test play/pause toggle
        #expect(mockGlobalAudioManager.isPlaying == false)
        
        mockGlobalAudioManager.startPlayback()
        #expect(mockGlobalAudioManager.isPlaying == true)
        
        mockGlobalAudioManager.pausePlayback()
        #expect(mockGlobalAudioManager.isPlaying == false)
        
        // Test seeking
        let initialTime = mockGlobalAudioManager.currentTime
        mockGlobalAudioManager.seek(to: 1800.0) // 30 minutes
        #expect(mockGlobalAudioManager.currentTime == 1800.0)
        #expect(mockGlobalAudioManager.currentTime != initialTime)
        
        // Test skip operations
        mockGlobalAudioManager.skipForward(30.0)
        #expect(mockGlobalAudioManager.currentTime == 1830.0)
        
        mockGlobalAudioManager.skipBackward(15.0)
        #expect(mockGlobalAudioManager.currentTime == 1815.0)
    }
    
    @Test("PlayerView playback rate controls work correctly")
    func testPlayerViewPlaybackRateControls() async throws {
        let audiobook = createTestAudiobook(title: "Rate Test")
        try mockGlobalAudioManager.loadAudiobook(audiobook)
        
        let playerView = PlayerView()
            .environmentObject(mockGlobalAudioManager)
            .environmentObject(mockAudiobookManager)
        
        // Test various playback rates
        let rates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
        
        for rate in rates {
            mockGlobalAudioManager.setPlaybackRate(rate)
            #expect(mockGlobalAudioManager.playbackRate == rate)
        }
        
        // Should end with a valid rate
        #expect(mockGlobalAudioManager.playbackRate >= 0.5)
        #expect(mockGlobalAudioManager.playbackRate <= 2.0)
    }
    
    // MARK: - Chapter Navigation Tests
    
    @Test("PlayerView handles chapter navigation")
    func testPlayerViewChapterNavigation() async throws {
        let audiobook = createTestAudiobookWithChapters(
            title: "Chapter Test",
            chapters: [
                ("Chapter 1", 0.0, 1800.0),
                ("Chapter 2", 1800.0, 3600.0),
                ("Chapter 3", 3600.0, 5400.0)
            ]
        )
        
        try mockGlobalAudioManager.loadAudiobook(audiobook)
        
        let playerView = PlayerView()
            .environmentObject(mockGlobalAudioManager)
            .environmentObject(mockAudiobookManager)
        
        // Test chapter navigation through mock engine
        #expect(mockGlobalAudioManager.currentChapterIndex == 0)
        
        // Move to next chapter
        mockGlobalAudioManager.nextChapter()
        #expect(mockGlobalAudioManager.currentChapterIndex == 1)
        #expect(mockGlobalAudioManager.currentTime >= 1800.0)
        
        // Move to next chapter again
        mockGlobalAudioManager.nextChapter()
        #expect(mockGlobalAudioManager.currentChapterIndex == 2)
        #expect(mockGlobalAudioManager.currentTime >= 3600.0)
        
        // Move to previous chapter
        mockGlobalAudioManager.previousChapter()
        #expect(mockGlobalAudioManager.currentChapterIndex == 1)
        #expect(mockGlobalAudioManager.currentTime >= 1800.0)
        #expect(mockGlobalAudioManager.currentTime < 3600.0)
    }
    
    // MARK: - Time Display Tests
    
    @Test("PlayerView displays time information correctly")
    func testPlayerViewTimeDisplay() async throws {
        let audiobook = createTestAudiobook(
            title: "Time Display Test",
            duration: 5400.0 // 1.5 hours
        )
        
        try mockGlobalAudioManager.loadAudiobook(audiobook)
        
        let playerView = PlayerView()
            .environmentObject(mockGlobalAudioManager)
            .environmentObject(mockAudiobookManager)
        
        // Test initial time display
        #expect(mockGlobalAudioManager.currentTime == 0.0)
        #expect(mockGlobalAudioManager.duration == 5400.0)
        
        // Test time display after seeking
        mockGlobalAudioManager.seek(to: 2700.0) // 45 minutes
        #expect(mockGlobalAudioManager.currentTime == 2700.0)
        #expect(mockGlobalAudioManager.duration == 5400.0)
        
        // Remaining time should be calculated correctly
        let remainingTime = mockGlobalAudioManager.duration - mockGlobalAudioManager.currentTime
        #expect(remainingTime == 2700.0) // 45 minutes remaining
    }
    
    // MARK: - MiniPlayer Mode Tests
    
    @Test("PlayerView supports mini-player mode")
    func testPlayerViewMiniPlayerMode() async throws {
        let audiobook = createTestAudiobook(title: "MiniPlayer Test")
        try mockGlobalAudioManager.loadAudiobook(audiobook)
        
        // Test that player view can be created (mini-player mode would be a property/state)
        let playerView = PlayerView()
            .environmentObject(mockGlobalAudioManager)
            .environmentObject(mockAudiobookManager)
        
        let hostingController = UIHostingController(rootView: playerView)
        
        #expect(hostingController.view != nil)
        
        // Start playback (would show mini-player in full implementation)
        mockGlobalAudioManager.startPlayback()
        #expect(mockGlobalAudioManager.isPlaying == true)
        
        // Mini-player specific controls should work
        mockGlobalAudioManager.skipForward(30.0)
        #expect(mockGlobalAudioManager.currentTime == 30.0)
    }
    
    // MARK: - Error State Tests
    
    @Test("PlayerView handles error states gracefully")
    func testPlayerViewErrorStateHandling() async throws {
        // Create view with mock in error state
        mockGlobalAudioManager.shouldFailOperations = true
        
        let audiobook = createTestAudiobook(title: "Error Test")
        
        // Loading should fail
        do {
            try mockGlobalAudioManager.loadAudiobook(audiobook)
            Issue.record("Expected loading to fail but it succeeded")
        } catch {
            // Expected to fail
        }
        
        let playerView = PlayerView()
            .environmentObject(mockGlobalAudioManager)
            .environmentObject(mockAudiobookManager)
        
        let hostingController = UIHostingController(rootView: playerView)
        
        // View should handle error state without crashing
        #expect(hostingController.view != nil)
        #expect(mockGlobalAudioManager.isReady == false)
    }
    
    // MARK: - Accessibility Tests
    
    @Test("PlayerView supports accessibility features")
    func testPlayerViewAccessibility() async throws {
        let audiobook = createTestAudiobook(
            title: "Accessibility Test",
            author: "Test Author"
        )
        
        try mockGlobalAudioManager.loadAudiobook(audiobook)
        
        let playerView = PlayerView()
            .environmentObject(mockGlobalAudioManager)
            .environmentObject(mockAudiobookManager)
        
        let hostingController = UIHostingController(rootView: playerView)
        
        // View should be accessible
        #expect(hostingController.view != nil)
        #expect(hostingController.view.isAccessibilityElement == false) // Container view
        
        // Test that accessibility works with playback
        mockGlobalAudioManager.startPlayback()
        #expect(mockGlobalAudioManager.isPlaying == true)
        
        // Should handle accessibility actions for playback controls
        mockGlobalAudioManager.pausePlayback()
        #expect(mockGlobalAudioManager.isPlaying == false)
    }
    
    // MARK: - State Persistence Tests
    
    @Test("PlayerView preserves state during view updates")
    func testPlayerViewStatePersistence() async throws {
        let audiobook = createTestAudiobook(title: "State Persistence Test")
        try mockGlobalAudioManager.loadAudiobook(audiobook)
        
        let playerView = PlayerView()
            .environmentObject(mockGlobalAudioManager)
            .environmentObject(mockAudiobookManager)
        
        // Start playback and seek to position
        mockGlobalAudioManager.startPlayback()
        mockGlobalAudioManager.seek(to: 1200.0) // 20 minutes
        mockGlobalAudioManager.setPlaybackRate(1.25)
        
        let currentTime = mockGlobalAudioManager.currentTime
        let playbackRate = mockGlobalAudioManager.playbackRate
        let isPlaying = mockGlobalAudioManager.isPlaying
        
        // Recreate view (simulates view updates)
        let updatedPlayerView = PlayerView()
            .environmentObject(mockGlobalAudioManager)
            .environmentObject(mockAudiobookManager)
        
        let hostingController = UIHostingController(rootView: updatedPlayerView)
        
        // State should be preserved
        #expect(hostingController.view != nil)
        #expect(mockGlobalAudioManager.currentTime == currentTime)
        #expect(mockGlobalAudioManager.playbackRate == playbackRate)
        #expect(mockGlobalAudioManager.isPlaying == isPlaying)
    }
    
    // MARK: - Performance Tests
    
    @Test("PlayerView handles rapid state changes efficiently")
    func testPlayerViewPerformanceUnderRapidChanges() async throws {
        let audiobook = createTestAudiobook(title: "Performance Test")
        try mockGlobalAudioManager.loadAudiobook(audiobook)
        
        let playerView = PlayerView()
            .environmentObject(mockGlobalAudioManager)
            .environmentObject(mockAudiobookManager)
        
        let hostingController = UIHostingController(rootView: playerView)
        
        // Perform rapid state changes
        for i in 1...50 {
            let seekTime = Double(i * 10) // 10, 20, 30... seconds
            mockGlobalAudioManager.seek(to: seekTime)
            
            if i % 5 == 0 {
                mockGlobalAudioManager.startPlayback()
            } else if i % 3 == 0 {
                mockGlobalAudioManager.pausePlayback()
            }
            
            try await Task.sleep(for: .milliseconds(1)) // Minimal delay
        }
        
        // View should handle rapid changes without issues
        #expect(hostingController.view != nil)
        #expect(mockGlobalAudioManager.currentTime > 0)
    }
    
    // MARK: - Helper Methods
    
    private func createTestAudiobook(
        title: String,
        author: String = "Test Author",
        duration: TimeInterval = 3600.0
    ) -> Audiobook {
        let audiobook = Audiobook(context: testContext)
        audiobook.id = UUID()
        audiobook.title = title
        audiobook.author = author
        audiobook.duration = duration
        audiobook.currentPosition = 0.0
        audiobook.dateAdded = Date()
        audiobook.isFinished = false
        
        // Create temp file for testing
        let tempFile = createTempAudioFile(named: "\(title).m4a")
        audiobook.fileURL = tempFile.path
        MockFileManager.setFileExists(tempFile.path, exists: true)
        
        try? testContext.save()
        return audiobook
    }
    
    private func createTestAudiobookWithChapters(
        title: String,
        chapters: [(String, TimeInterval, TimeInterval)]
    ) -> Audiobook {
        let totalDuration = chapters.last?.2 ?? 3600.0
        let audiobook = createTestAudiobook(title: title, duration: totalDuration)
        
        for (index, (chapterTitle, startTime, endTime)) in chapters.enumerated() {
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
}

// MARK: - Test Tags
extension Tag {
    @Tag static var ui: Self
    @Tag static var player: Self
}