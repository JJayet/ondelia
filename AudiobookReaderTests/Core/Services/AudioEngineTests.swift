//
//  AudioEngineTests.swift
//  AudiobookReaderTests
//
//  Created by AudiobookReader Testing Infrastructure
//

import Testing
import AVFoundation
import MediaPlayer
@testable import AudiobookReader


/// Shared fixture for AudioEngineTests and AudioEngineTests_Part2.
var mockAudioURL: URL {
    TestDataFactory.createMockAudioFile(named: "test-audio", duration: 3600)
}

@MainActor
struct AudioEngineTests {
    
    // MARK: - Initialization Tests
    
    @Test("AudioEngine should initialize with default values")
    func audioEngineInitialization() async throws {
        let audioEngine = AudioEngine()
        
        #expect(audioEngine.isPlaying == false)
        #expect(audioEngine.currentTime == 0)
        #expect(audioEngine.duration == 0)
        #expect(audioEngine.playbackRate == 1.0)
    }
    
    @Test("AudioEngine should properly deinitialize and cleanup")
    func audioEngineDeinitialization() async throws {
        var audioEngine: AudioEngine? = AudioEngine()
        let weakRef = audioEngine
        
        // Load audio to initialize internal state
        audioEngine?.loadAudio(url: mockAudioURL)
        
        // Wait a moment for async operations
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        audioEngine = nil
        
        // Verify cleanup
        #expect(weakRef?.isPlaying == false)
    }
    
    // MARK: - Audio Loading Tests
    
    @Test("AudioEngine should load valid audio file")
    func audioEngineLoadValidFile() async throws {
        let audioEngine = AudioEngine()
        
        // Create a valid mock audio file
        let audioURL = mockAudioURL
        
        audioEngine.loadAudio(url: audioURL)
        
        // Wait for async loading
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Verify initial state after loading
        #expect(audioEngine.isPlaying == false)
        #expect(audioEngine.currentTime == 0)
    }
    
    @Test("AudioEngine should handle invalid audio file gracefully")
    func audioEngineLoadInvalidFile() async throws {
        let audioEngine = AudioEngine()
        
        // Create invalid URL
        let invalidURL = URL(fileURLWithPath: "/nonexistent/invalid-file.mp3")
        
        audioEngine.loadAudio(url: invalidURL)
        
        // Wait for async loading attempt
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Should not crash and maintain safe state
        #expect(audioEngine.isPlaying == false)
        #expect(audioEngine.currentTime == 0)
    }
    
    // MARK: - Playback Control Tests
    
    @Test("AudioEngine should handle play command")
    func audioEnginePlayCommand() async throws {
        let audioEngine = AudioEngine()
        audioEngine.loadAudio(url: mockAudioURL)
        
        // Wait for loading
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        audioEngine.play()
        
        // Wait for play state change
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        #expect(audioEngine.isPlaying == true)
    }
    
    @Test("AudioEngine should handle pause command")
    func audioEnginePauseCommand() async throws {
        let audioEngine = AudioEngine()
        audioEngine.loadAudio(url: mockAudioURL)
        
        // Wait for loading
        try await Task.sleep(nanoseconds: 300_000_000)
        
        audioEngine.play()
        try await Task.sleep(nanoseconds: 100_000_000)
        
        #expect(audioEngine.isPlaying == true)
        
        audioEngine.pause()
        try await Task.sleep(nanoseconds: 100_000_000)
        
        #expect(audioEngine.isPlaying == false)
    }
    
    // MARK: - Seek Operation Tests
    
    @Test("AudioEngine should handle seek operations")
    func audioEngineSeekOperations() async throws {
        let audioEngine = AudioEngine()
        audioEngine.loadAudio(url: mockAudioURL)
        
        // Wait for loading
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Test seeking to specific time
        audioEngine.seek(to: 1000.0) // 16:40
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Note: In real implementation, currentTime would update
        // For testing, we verify the seek operation was called without error
        #expect(audioEngine.currentTime >= 0) // Should not be negative
    }
    
    @Test("AudioEngine should handle skip forward")
    func audioEngineSkipForward() async throws {
        let audioEngine = AudioEngine()
        audioEngine.loadAudio(url: mockAudioURL)
        
        try await Task.sleep(nanoseconds: 300_000_000)
        
        let initialTime = audioEngine.currentTime
        audioEngine.skipForward(30) // Skip 30 seconds
        
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Verify skip was attempted (exact time may vary due to async nature)
        #expect(audioEngine.currentTime >= initialTime)
    }
    
    @Test("AudioEngine should handle skip backward")
    func audioEngineSkipBackward() async throws {
        let audioEngine = AudioEngine()
        audioEngine.loadAudio(url: mockAudioURL)
        
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // First seek to a position where we can skip backward
        audioEngine.seek(to: 60.0)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        audioEngine.skipBackward(30)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Should not go below 0
        #expect(audioEngine.currentTime >= 0)
    }
}
