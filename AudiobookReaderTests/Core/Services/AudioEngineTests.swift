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
@Suite(.serialized)
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
        weak var weakRef = audioEngine
        
        // Load audio to initialize internal state
        audioEngine?.loadAudio(url: mockAudioURL)
        
        #expect(await waitUntil { audioEngine?.player != nil })
        
        audioEngine = nil
        
        #expect(await waitUntil { weakRef == nil })
    }
    
    // MARK: - Audio Loading Tests
    
    @Test("AudioEngine should load valid audio file")
    func audioEngineLoadValidFile() async throws {
        let audioEngine = AudioEngine()
        
        // Create a valid mock audio file
        let audioURL = mockAudioURL
        
        audioEngine.loadAudio(url: audioURL)
        
        #expect(await waitUntil { audioEngine.duration > 30 })
        
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
        
        // Should not crash and maintain safe state
        #expect(audioEngine.isPlaying == false)
        #expect(audioEngine.currentTime == 0)
        #expect(audioEngine.player == nil)
    }
    
    // MARK: - Playback Control Tests
    
    @Test("AudioEngine should handle play command")
    func audioEnginePlayCommand() async throws {
        let audioEngine = AudioEngine()
        audioEngine.loadAudio(url: mockAudioURL)
        
        #expect(await waitUntil { audioEngine.player != nil })
        
        audioEngine.play()
        
        #expect(await waitUntil { audioEngine.isPlaying })
    }
    
    @Test("AudioEngine should handle pause command")
    func audioEnginePauseCommand() async throws {
        let audioEngine = AudioEngine()
        audioEngine.loadAudio(url: mockAudioURL)
        
        #expect(await waitUntil { audioEngine.player != nil })
        
        audioEngine.play()
        #expect(await waitUntil { audioEngine.isPlaying })
        
        audioEngine.pause()
        #expect(await waitUntil { !audioEngine.isPlaying })
    }
    
    // MARK: - Seek Operation Tests
    
    @Test("AudioEngine should handle seek operations")
    func audioEngineSeekOperations() async throws {
        let audioEngine = AudioEngine()
        audioEngine.loadAudio(url: mockAudioURL)
        
        #expect(await waitUntil { audioEngine.player != nil })
        
        // Test seeking to specific time
        audioEngine.seek(to: 1000.0) // 16:40
        #expect(await waitUntil {
            (audioEngine.player?.currentTime().seconds ?? 0) >= 999
        })
    }
    
    @Test("AudioEngine should handle skip forward")
    func audioEngineSkipForward() async throws {
        let audioEngine = AudioEngine()
        audioEngine.loadAudio(url: mockAudioURL)
        
        #expect(await waitUntil { audioEngine.duration > 30 })
        
        let initialTime = audioEngine.currentTime
        audioEngine.skipForward(30) // Skip 30 seconds
        #expect(await waitUntil {
            (audioEngine.player?.currentTime().seconds ?? 0) >= initialTime + 29
        })
    }
    
    @Test("AudioEngine should handle skip backward")
    func audioEngineSkipBackward() async throws {
        let audioEngine = AudioEngine()
        audioEngine.loadAudio(url: mockAudioURL)
        
        #expect(await waitUntil { audioEngine.player != nil })
        
        // First seek to a position where we can skip backward
        audioEngine.seek(to: 60.0)
        #expect(await waitUntil {
            (audioEngine.player?.currentTime().seconds ?? 0) >= 59
        })
        
        audioEngine.skipBackward(30)
        #expect(await waitUntil {
            let time = audioEngine.player?.currentTime().seconds ?? .infinity
            return time >= 29 && time <= 31
        })
    }
}
