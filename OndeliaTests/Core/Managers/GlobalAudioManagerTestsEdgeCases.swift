//
//  GlobalAudioManagerTestsEdgeCases.swift
//  IsoraTests
//
//  Split from GlobalAudioManagerTests.swift (errors, position, memory, processing, concurrency)
//

import Testing
import Foundation
@testable import Isora

extension GlobalAudioManagerTests {
    /// Child suite of GlobalAudioManagerTests: inherits the parent's `.serialized`, so it never
    /// runs concurrently with part 1 (both drive GlobalAudioManager.shared).
    @MainActor
    @Suite("GlobalAudioManager Tests (Edge Cases)", .serialized, .tags(.manager))
    struct EdgeCases {
        
        // MARK: - Error Handling Tests
    
        @Test("Missing file path results in failed state")
        func testMissingFilePathHandling() async throws {
            let manager = GlobalAudioManager.shared
            let audiobook = createTestAudiobook(isMultiFile: false)
        
            // Leave fileURL nil
            audiobook.fileURL = nil
        
            manager.loadAudiobook(audiobook)
            #expect(await waitUntil { !manager.isLoading })
        
            #expect(manager.isLoading == false)
            #expect(manager.playbackState == .failed)
            #expect(manager.player == nil)
        }
    
        @Test("Non-existent file results in failed state")
        func testNonExistentFileHandling() async throws {
            let manager = GlobalAudioManager.shared
            let audiobook = createTestAudiobook(isMultiFile: false)
        
            audiobook.fileURL = "/non/existent/path/file.m4a"
        
            manager.loadAudiobook(audiobook)
            #expect(await waitUntil { !manager.isLoading })
        
            #expect(manager.isLoading == false)
            #expect(manager.playbackState == .failed)
            #expect(manager.player == nil)
        }
    
        // MARK: - Position Management Tests
    
        @Test("Current position is restored when reloading same audiobook")
        func testPositionRestoration() async throws {
            let manager = GlobalAudioManager.shared
            let audiobook = createTestAudiobook(isMultiFile: false)
        
            let tempURL = createTempAudioFile(named: "position_test.m4a")
            defer { removeTempItems(tempURL) }
            audiobook.fileURL = tempURL.path
            audiobook.currentPosition = 1500.0 // 25 minutes in
        
            manager.loadAudiobook(audiobook)
            #expect(await waitUntil { !manager.isLoading })
        
            #expect(manager.getCurrentTime() >= 1490.0) // Allow some variance
            #expect(manager.getCurrentTime() <= 1510.0)
        }
    
        // MARK: - Memory Management Tests
    
        @Test("Loading another book tears the previous player down")
        func testEngineCleanup() async throws {
            let manager = GlobalAudioManager.shared
        
            // Create and load audiobook
            let audiobook = createTestAudiobook(isMultiFile: false)
            let tempURL = createTempAudioFile(named: "cleanup_test.m4a")
            audiobook.fileURL = tempURL.path
        
            manager.loadAudiobook(audiobook)
            #expect(await waitUntil { !manager.isLoading })
        
            let firstPlayer = try #require(manager.player)
        
            // Load a different audiobook to trigger teardown
            let audiobook2 = createTestAudiobook(isMultiFile: true)
            let tempDir2 = createTestChapterFolder(named: "cleanup_test2", chapters: 2)
            defer { removeTempItems(tempURL, tempDir2) }
            audiobook2.fileURL = tempDir2.path
        
            manager.loadAudiobook(audiobook2)
            #expect(await waitUntil { !manager.isLoading })
        
            let secondPlayer = try #require(manager.player)
            #expect(secondPlayer !== firstPlayer)
            #expect(secondPlayer.tracks.count == 2)
            // The replaced player is emptied rather than left holding a live queue.
            #expect(firstPlayer.tracks.isEmpty)
            #expect(firstPlayer.player.items().isEmpty)
        }
    
        // MARK: - Audio Processing Features Tests
    
        @Test("Audio processing controls are properly delegated")
        func testAudioProcessingControls() async throws {
            let manager = GlobalAudioManager.shared
            let audiobook = createTestAudiobook(isMultiFile: false)
        
            let tempURL = createTempAudioFile(named: "processing_test.m4a")
            defer { removeTempItems(tempURL) }
            audiobook.fileURL = tempURL.path
        
            manager.loadAudiobook(audiobook)
            #expect(await waitUntil { !manager.isLoading })
        
            // Test playback rate
            manager.setPlaybackRate(1.5)
            #expect(manager.getPlaybackRate() == 1.5)
        
            // Verify no exceptions thrown and state remains stable
            #expect(manager.isReady == true)
            #expect(manager.player != nil)
        }
    
        // MARK: - Concurrent Operations Tests
    
        @Test("Concurrent audiobook loading is handled safely")
        func testConcurrentLoading() async throws {
            let manager = GlobalAudioManager.shared
        
            // Create multiple audiobooks
            let audiobook1 = createTestAudiobook(isMultiFile: false, title: "Concurrent Test 1")
            let audiobook2 = createTestAudiobook(isMultiFile: false, title: "Concurrent Test 2")
            let audiobook3 = createTestAudiobook(isMultiFile: true, title: "Concurrent Test 3")
        
            let tempURL1 = createTempAudioFile(named: "concurrent1.m4a")
            let tempURL2 = createTempAudioFile(named: "concurrent2.m4a")
            let tempDir3 = createTestChapterFolder(named: "concurrent3", chapters: 2)
            defer { removeTempItems(tempURL1, tempURL2, tempDir3) }
        
            audiobook1.fileURL = tempURL1.path
            audiobook2.fileURL = tempURL2.path
            audiobook3.fileURL = tempDir3.path
        
        
            // Three requests back to back: each supersedes the one still loading, and the
            // last one wins. `loadAudiobook` returns immediately and finishes in a Task.
            manager.loadAudiobook(audiobook1)
            manager.loadAudiobook(audiobook2)
            manager.loadAudiobook(audiobook3)

            #expect(await waitUntil { !manager.isLoading })
        
            #expect(manager.currentAudiobook?.id == audiobook3.id)
            #expect(manager.isReady == true)
            #expect(manager.isLoading == false)
        
            // One player, whichever book won the race, and only one.
            let player = try #require(manager.player)
            #expect(player.tracks.isEmpty == false)
        }
    }
}
