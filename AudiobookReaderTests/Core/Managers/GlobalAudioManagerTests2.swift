//
//  GlobalAudioManagerTests2.swift
//  AudiobookReaderTests
//
//  Split from GlobalAudioManagerTests.swift (errors, position, memory, processing, concurrency)
//

import Testing
import Foundation
import Combine
@testable import AudiobookReader

extension GlobalAudioManagerTests {
    /// Child suite of GlobalAudioManagerTests: inherits the parent's `.serialized`, so it never
    /// runs concurrently with part 1 (both drive GlobalAudioManager.shared).
    /// Serialized order follows source location (fileID first): this file must sort after
    /// GlobalAudioManagerTests.swift so testInitializationState() still sees a pristine singleton.
    @MainActor
    @Suite("GlobalAudioManager Tests (2)", .serialized, .tags(.manager))
    struct Part2 {
        
        init() {
            // Reset mock framework for each test
            MockAVAudioSession.reset()
            MockFileManager.reset()
        }
        
        // MARK: - Error Handling Tests
    
        @Test("Missing file path results in failed state")
        func testMissingFilePathHandling() async throws {
            let manager = GlobalAudioManager.shared
            let audiobook = createTestAudiobook(isMultiFile: false)
        
            // Leave fileURL nil
            audiobook.fileURL = nil
        
            await manager.loadAudiobook(audiobook)
            try await Task.sleep(for: .milliseconds(200))
        
            #expect(manager.isLoading == false)
            #expect(manager.playbackState == .failed)
            #expect(manager.audioEngine == nil)
            #expect(manager.multiFileAudioEngine == nil)
        }
    
        @Test("Non-existent file results in failed state")
        func testNonExistentFileHandling() async throws {
            let manager = GlobalAudioManager.shared
            let audiobook = createTestAudiobook(isMultiFile: false)
        
            audiobook.fileURL = "/non/existent/path/file.m4a"
            MockFileManager.setFileExists("/non/existent/path/file.m4a", exists: false)
        
            await manager.loadAudiobook(audiobook)
            try await Task.sleep(for: .milliseconds(200))
        
            #expect(manager.isLoading == false)
            #expect(manager.playbackState == .failed)
            #expect(manager.audioEngine == nil)
            #expect(manager.multiFileAudioEngine == nil)
        }
    
        // MARK: - Position Management Tests
    
        @Test("Current position is restored when reloading same audiobook")
        func testPositionRestoration() async throws {
            let manager = GlobalAudioManager.shared
            let audiobook = createTestAudiobook(isMultiFile: false)
        
            let tempURL = createTempAudioFile(named: "position_test.m4a")
            audiobook.fileURL = tempURL.path
            audiobook.currentPosition = 1500.0 // 25 minutes in
            MockFileManager.setFileExists(tempURL.path, exists: true)
        
            await manager.loadAudiobook(audiobook)
            try await Task.sleep(for: .milliseconds(300))
        
            #expect(manager.getCurrentTime() >= 1490.0) // Allow some variance
            #expect(manager.getCurrentTime() <= 1510.0)
        }
    
        // MARK: - Memory Management Tests
    
        @Test("Engine cleanup properly deallocates resources")
        func testEngineCleanup() async throws {
            let manager = GlobalAudioManager.shared
        
            // Create and load audiobook
            let audiobook = createTestAudiobook(isMultiFile: false)
            let tempURL = createTempAudioFile(named: "cleanup_test.m4a")
            audiobook.fileURL = tempURL.path
            MockFileManager.setFileExists(tempURL.path, exists: true)
        
            await manager.loadAudiobook(audiobook)
            try await Task.sleep(for: .milliseconds(300))
        
            let engineReference = manager.audioEngine
            #expect(engineReference != nil)
        
            // Load different audiobook to trigger cleanup
            let audiobook2 = createTestAudiobook(isMultiFile: true)
            let tempDir2 = createTempDirectory(named: "cleanup_test2")
            audiobook2.fileURL = tempDir2.path
            MockFileManager.setFileExists(tempDir2.path, exists: true)
        
            await manager.loadAudiobook(audiobook2)
            try await Task.sleep(for: .milliseconds(300))
        
            // Original engine should be cleared
            #expect(manager.audioEngine == nil)
            #expect(manager.multiFileAudioEngine != nil)
        }
    
        // MARK: - Audio Processing Features Tests
    
        @Test("Audio processing controls are properly delegated")
        func testAudioProcessingControls() async throws {
            let manager = GlobalAudioManager.shared
            let audiobook = createTestAudiobook(isMultiFile: false)
        
            let tempURL = createTempAudioFile(named: "processing_test.m4a")
            audiobook.fileURL = tempURL.path
            MockFileManager.setFileExists(tempURL.path, exists: true)
        
            await manager.loadAudiobook(audiobook)
            try await Task.sleep(for: .milliseconds(300))
        
            // Test playback rate
            manager.setPlaybackRate(1.5)
            #expect(manager.getPlaybackRate() == 1.5)
        
            // Verify no exceptions thrown and state remains stable
            #expect(manager.isReady == true)
            #expect(manager.audioEngine != nil)
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
            let tempDir3 = createTempDirectory(named: "concurrent3")
        
            audiobook1.fileURL = tempURL1.path
            audiobook2.fileURL = tempURL2.path
            audiobook3.fileURL = tempDir3.path
        
            MockFileManager.setFileExists(tempURL1.path, exists: true)
            MockFileManager.setFileExists(tempURL2.path, exists: true)
            MockFileManager.setFileExists(tempDir3.path, exists: true)
        
            // Start concurrent loading operations
            async let load1 = manager.loadAudiobook(audiobook1)
            async let load2 = manager.loadAudiobook(audiobook2)
            async let load3 = manager.loadAudiobook(audiobook3)
        
            // Wait for all to complete
            await load1
            await load2
            await load3
        
            try await Task.sleep(for: .milliseconds(500))
        
            // Should have one audiobook loaded (the last one processed)
            #expect(manager.currentAudiobook != nil)
            #expect(manager.isReady == true)
            #expect(manager.isLoading == false)
        
            // Should have correct engine type for the final audiobook
            let finalIsMultiFile = manager.useMultiFileEngine
            if finalIsMultiFile {
                #expect(manager.multiFileAudioEngine != nil)
                #expect(manager.audioEngine == nil)
            } else {
                #expect(manager.audioEngine != nil)
                #expect(manager.multiFileAudioEngine == nil)
            }
        }
    }
}
