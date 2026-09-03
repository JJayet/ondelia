//
//  AudioEngineTests2.swift
//  AudiobookReaderTests
//
//  Split from AudioEngineTests.swift (rate, memory, concurrency, interruptions, performance, consistency)
//

import Testing
import AVFoundation
import MediaPlayer
@testable import AudiobookReader

@MainActor
struct AudioEngineTests_Part2 {

    // MARK: - Playback Rate Tests
    
    @Test("AudioEngine should handle playback rate changes")
    func audioEnginePlaybackRateChanges() async throws {
        let audioEngine = AudioEngine()
        audioEngine.loadAudio(url: mockAudioURL)
        
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Test various playback rates
        let testRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
        
        for rate in testRates {
            audioEngine.setPlaybackRate(rate)
            try await Task.sleep(nanoseconds: 100_000_000)
            
            #expect(audioEngine.playbackRate == rate)
        }
    }
    
    @Test("AudioEngine should handle extreme playback rates")
    func audioEngineExtremePlaybackRates() async throws {
        let audioEngine = AudioEngine()
        audioEngine.loadAudio(url: mockAudioURL)
        
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Test edge cases
        audioEngine.setPlaybackRate(0.25) // Very slow
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(audioEngine.playbackRate == 0.25)
        
        audioEngine.setPlaybackRate(3.0) // Very fast
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(audioEngine.playbackRate == 3.0)
        
        // Test invalid rates (should be handled gracefully)
        audioEngine.setPlaybackRate(-1.0) // Negative rate
        try await Task.sleep(nanoseconds: 100_000_000)
        
        audioEngine.setPlaybackRate(0.0) // Zero rate
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    
    // MARK: - Memory Management Tests
    
    @Test("AudioEngine should handle multiple load operations")
    func audioEngineMultipleLoadOperations() async throws {
        let audioEngine = AudioEngine()
        
        // Load first file
        let audioURL1 = TestDataFactory.createMockAudioFile(named: "test1", duration: 1800)
        audioEngine.loadAudio(url: audioURL1)
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Load second file (should replace first)
        let audioURL2 = TestDataFactory.createMockAudioFile(named: "test2", duration: 3600)
        audioEngine.loadAudio(url: audioURL2)
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Should still be in valid state
        #expect(audioEngine.isPlaying == false)
        #expect(audioEngine.currentTime == 0)
    }
    
    @Test("AudioEngine should cleanup properly after multiple operations")
    func audioEngineCleanupAfterOperations() async throws {
        var audioEngine: AudioEngine? = AudioEngine()
        weak var weakEngine = audioEngine
        
        audioEngine?.loadAudio(url: mockAudioURL)
        try await Task.sleep(nanoseconds: 300_000_000)
        
        audioEngine?.play()
        try await Task.sleep(nanoseconds: 100_000_000)
        
        audioEngine?.pause()
        try await Task.sleep(nanoseconds: 100_000_000)
        
        audioEngine?.seek(to: 500.0)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        audioEngine = nil
        
        // Give time for cleanup
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Should be deallocated
        #expect(weakEngine == nil)
    }
    
    // MARK: - Thread Safety Tests
    
    @Test("AudioEngine should handle concurrent operations")
    func audioEngineConcurrentOperations() async throws {
        let audioEngine = AudioEngine()
        audioEngine.loadAudio(url: mockAudioURL)
        
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Simulate concurrent operations
        await withTaskGroup(of: Void.self) { group in
            // Concurrent playback toggles
            group.addTask {
                for _ in 0..<10 {
                    audioEngine.togglePlayback()
                    try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
                }
            }
            
            // Concurrent seek operations
            group.addTask {
                for i in 0..<10 {
                    audioEngine.seek(to: Double(i * 60)) // Seek to different positions
                    try? await Task.sleep(nanoseconds: 10_000_000)
                }
            }
            
            // Concurrent rate changes
            group.addTask {
                let rates: [Float] = [1.0, 1.25, 1.5, 1.0]
                for rate in rates {
                    audioEngine.setPlaybackRate(rate)
                    try? await Task.sleep(nanoseconds: 25_000_000) // 0.025 seconds
                }
            }
        }
        
        // Wait for all operations to complete
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Engine should still be in a valid state
        #expect(audioEngine.playbackRate >= 0.5)
        #expect(audioEngine.playbackRate <= 2.0)
        #expect(audioEngine.currentTime >= 0)
    }
    
    // MARK: - Error Handling Tests
    
    @Test("AudioEngine should handle system audio interruptions gracefully")
    func audioEngineSystemInterruptions() async throws {
        let audioEngine = AudioEngine()
        audioEngine.loadAudio(url: mockAudioURL)
        
        try await Task.sleep(nanoseconds: 300_000_000)
        
        audioEngine.play()
        try await Task.sleep(nanoseconds: 100_000_000)
        
        #expect(audioEngine.isPlaying == true)
        
        // Simulate audio interruption by manually calling the interruption handler
        let interruptionNotification = Notification(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
            ]
        )
        
        NotificationCenter.default.post(interruptionNotification)
        
        // Wait for interruption handling
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Should pause playback during interruption
        #expect(audioEngine.isPlaying == false)
    }
    
    // MARK: - Performance Tests
    
    @Test("AudioEngine should load audio quickly")
    func audioEngineLoadPerformance() async throws {
        let audioEngine = AudioEngine()
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        audioEngine.loadAudio(url: mockAudioURL)
        
        // Wait for basic loading to complete
        try await Task.sleep(nanoseconds: 500_000_000)
        
        let loadTime = CFAbsoluteTimeGetCurrent() - startTime
        
        // Should load within reasonable time (allowing for async operations)
        #expect(loadTime < TestConfiguration.maxAcceptableLoadTime)
    }
    
    // MARK: - State Consistency Tests
    
    @Test("AudioEngine should maintain consistent state during rapid operations")
    func audioEngineStateConsistency() async throws {
        let audioEngine = AudioEngine()
        audioEngine.loadAudio(url: mockAudioURL)
        
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Rapid state changes
        for _ in 0..<20 {
            audioEngine.play()
            try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
            
            audioEngine.pause()
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        
        // Final state should be consistent
        #expect(audioEngine.isPlaying == false)
        #expect(audioEngine.currentTime >= 0)
        #expect(audioEngine.duration >= 0)
    }
    
    // Note: Cleanup is handled by individual test methods and TestDataFactory as needed
}
