//
//  GlobalAudioManagerTests.swift
//  AudiobookReaderTests
//
//  Created by AudiobookReader Testing Infrastructure - Phase 2
//

import Testing
import Foundation
@testable import AudiobookReader

@MainActor
@Suite("GlobalAudioManager Tests", .serialized, .tags(.manager))
struct GlobalAudioManagerTests {

    init() {
        // Reset mock framework for each test
        MockAVAudioSession.reset()
        MockFileManager.reset()
    }
    
    // MARK: - Initialization Tests
    
    @Test("GlobalAudioManager initializes with correct default state")
    func testInitializationState() async throws {
        let manager = GlobalAudioManager.shared
        
        #expect(manager.currentAudiobook == nil)
        #expect(manager.player == nil)
        #expect(manager.isLoading == false)
        #expect(manager.isReady == false)
        #expect(manager.showMiniPlayer == false)
        #expect(manager.playbackState == .stopped)
    }
    
    // MARK: - Engine Selection Tests
    
    @Test("A single-file book loads as one track")
    func testSingleFileEngineSelection() async throws {
        let manager = GlobalAudioManager.shared
        let audiobook = createTestAudiobook(isMultiFile: false)
        
        // Create temp file for testing
        let tempURL = createTempAudioFile(named: "test_single.m4a")
        audiobook.fileURL = tempURL.path
        
        // Mock file existence
        MockFileManager.setFileExists(tempURL.path, exists: true)
        
        manager.loadAudiobook(audiobook)
        
        // Wait for loading to complete
        try await Task.sleep(for: .milliseconds(500))
        
        #expect(manager.player?.tracks.count == 1)
        #expect(manager.currentAudiobook?.id == audiobook.id)
    }
    
    @Test("A folder book loads one track per chapter")
    func testMultiFileEngineSelection() async throws {
        let manager = GlobalAudioManager.shared
        let audiobook = createTestAudiobook(isMultiFile: true)
        
        let tempDir = createTestChapterFolder(named: "test_multifile", chapters: 3)
        audiobook.fileURL = tempDir.path
        
        // Mock directory existence
        MockFileManager.setFileExists(tempDir.path, exists: true)
        
        manager.loadAudiobook(audiobook)
        
        // Wait for loading to complete
        try await Task.sleep(for: .milliseconds(500))
        
        #expect(manager.player?.tracks.count == 3)
        #expect(manager.currentAudiobook?.id == audiobook.id)
    }
    
    // MARK: - Engine Switching Tests
    
    @Test("Switching books replaces the player and its timeline")
    func testEngineSwitching() async throws {
        let manager = GlobalAudioManager.shared
        
        // Load first audiobook (single file)
        let audiobook1 = createTestAudiobook(isMultiFile: false)
        let tempURL1 = createTempAudioFile(named: "test1.m4a")
        audiobook1.fileURL = tempURL1.path
        MockFileManager.setFileExists(tempURL1.path, exists: true)
        
        manager.loadAudiobook(audiobook1)
        try await Task.sleep(for: .milliseconds(300))
        
        #expect(manager.player?.tracks.count == 1)
        
        // Load second audiobook (multi-file)
        let audiobook2 = createTestAudiobook(isMultiFile: true)
        let tempDir2 = createTestChapterFolder(named: "test2_multifile", chapters: 2)
        audiobook2.fileURL = tempDir2.path
        MockFileManager.setFileExists(tempDir2.path, exists: true)
        
        manager.loadAudiobook(audiobook2)
        try await Task.sleep(for: .milliseconds(300))
        
        #expect(manager.player?.tracks.count == 2)
        #expect(manager.currentAudiobook?.id == audiobook2.id)
    }
    
    // MARK: - State Management Tests
    
    @Test("Loading state properly transitions during audiobook loading")
    func testLoadingStateTransitions() async throws {
        let manager = GlobalAudioManager.shared
        let audiobook = createTestAudiobook(isMultiFile: false)
        
        let tempURL = createTempAudioFile(named: "state_test.m4a")
        audiobook.fileURL = tempURL.path
        MockFileManager.setFileExists(tempURL.path, exists: true)
        
        // Start loading
        manager.loadAudiobook(audiobook)
        
        // Should be loading immediately
        #expect(manager.isLoading == true)
        #expect(manager.playbackState == .loading)
        
        // Wait for loading to complete
        try await Task.sleep(for: .milliseconds(600))
        
        // Should be ready after loading
        #expect(manager.isLoading == false)
        #expect(manager.isReady == true)
        #expect(manager.playbackState == .paused)
    }
    
    @Test("Playback state updates correctly during play/pause operations")
    func testPlaybackStateManagement() async throws {
        let manager = GlobalAudioManager.shared
        let audiobook = createTestAudiobook(isMultiFile: false)
        
        let tempURL = createTempAudioFile(named: "playback_test.m4a")
        audiobook.fileURL = tempURL.path
        MockFileManager.setFileExists(tempURL.path, exists: true)
        
        // Load audiobook
        manager.loadAudiobook(audiobook)
        try await Task.sleep(for: .milliseconds(300))
        
        // Test play state
        // ponytail: isPlaying() reads AVPlayer.rate, which stays 0 for the empty fixture; add a real audio file to assert it.
        manager.startPlayback()
        #expect(manager.playbackState == .playing)
        #expect(manager.showMiniPlayer == true)
        
        // Test pause state
        manager.pausePlayback()
        #expect(manager.playbackState == .paused)
        #expect(manager.isPlaying() == false)
        
        // Test resume state
        manager.resumePlayback()
        #expect(manager.playbackState == .playing)
        #expect(manager.showMiniPlayer == true)
        
        // Test stop state
        manager.stopPlayback()
        #expect(manager.playbackState == .stopped)
        #expect(manager.showMiniPlayer == false)
        #expect(manager.isPlaying() == false)
    }
}

// MARK: - Test Tags
extension Tag {
    @Tag static var manager: Self
}
