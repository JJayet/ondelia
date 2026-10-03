//
//  GlobalAudioManagerTests.swift
//  IsoraTests
//
//  Created by Isora Testing Infrastructure - Phase 2
//

import Testing
import Foundation
@testable import Isora

@MainActor
@Suite("GlobalAudioManager Tests", .serialized, .tags(.manager))
struct GlobalAudioManagerTests {

    // MARK: - Initialization Tests

    @Test("Unloading returns GlobalAudioManager to its default state")
    func testInitializationState() async throws {
        let manager = GlobalAudioManager.shared
        // The singleton outlives every test, so start from a known state rather than test order.
        manager.unload()

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
        defer { removeTempItems(tempURL) }
        audiobook.fileURL = tempURL.path

        manager.loadAudiobook(audiobook)

        #expect(await waitUntil { !manager.isLoading })

        #expect(manager.player?.tracks.count == 1)
        #expect(manager.currentAudiobook?.id == audiobook.id)
    }

    @Test("A folder book loads one track per chapter")
    func testMultiFileEngineSelection() async throws {
        let manager = GlobalAudioManager.shared
        let audiobook = createTestAudiobook(isMultiFile: true)

        let tempDir = createTestChapterFolder(named: "test_multifile", chapters: 3)
        defer { removeTempItems(tempDir) }
        audiobook.fileURL = tempDir.path

        manager.loadAudiobook(audiobook)

        #expect(await waitUntil { !manager.isLoading })

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

        manager.loadAudiobook(audiobook1)
        #expect(await waitUntil { !manager.isLoading })

        #expect(manager.player?.tracks.count == 1)

        // Load second audiobook (multi-file)
        let audiobook2 = createTestAudiobook(isMultiFile: true)
        let tempDir2 = createTestChapterFolder(named: "test2_multifile", chapters: 2)
        defer { removeTempItems(tempURL1, tempDir2) }
        audiobook2.fileURL = tempDir2.path

        manager.loadAudiobook(audiobook2)
        #expect(await waitUntil { !manager.isLoading })

        #expect(manager.player?.tracks.count == 2)
        #expect(manager.currentAudiobook?.id == audiobook2.id)
    }

    // MARK: - State Management Tests

    @Test("Loading state properly transitions during audiobook loading")
    func testLoadingStateTransitions() async throws {
        let manager = GlobalAudioManager.shared
        let audiobook = createTestAudiobook(isMultiFile: false)

        let tempURL = createTempAudioFile(named: "state_test.m4a")
        defer { removeTempItems(tempURL) }
        audiobook.fileURL = tempURL.path

        // Start loading
        manager.loadAudiobook(audiobook)

        // Should be loading immediately
        #expect(manager.isLoading == true)
        #expect(manager.playbackState == .loading)

        #expect(await waitUntil { !manager.isLoading })

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
        defer { removeTempItems(tempURL) }
        audiobook.fileURL = tempURL.path

        // Load audiobook
        manager.loadAudiobook(audiobook)
        #expect(await waitUntil { manager.isReady })

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
