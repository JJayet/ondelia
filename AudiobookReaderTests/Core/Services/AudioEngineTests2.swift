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
@Suite(.serialized)
struct AudioEngineTests_Part2 {

    // MARK: - Playback Rate Tests
    
    @Test("AudioEngine should handle playback rate changes")
    func audioEnginePlaybackRateChanges() async throws {
        let audioEngine = AudioEngine()
        audioEngine.loadAudio(url: mockAudioURL)
        
        #expect(await waitUntil { audioEngine.player != nil })
        
        // Test various playback rates
        let testRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
        
        for rate in testRates {
            audioEngine.setPlaybackRate(rate)
            #expect(await waitUntil { audioEngine.playbackRate == rate })
        }
    }
    
    @Test("AudioEngine should handle extreme playback rates")
    func audioEngineExtremePlaybackRates() async throws {
        let audioEngine = AudioEngine()
        audioEngine.loadAudio(url: mockAudioURL)
        
        #expect(await waitUntil { audioEngine.player != nil })
        
        // Test edge cases
        audioEngine.setPlaybackRate(0.25) // Very slow
        #expect(await waitUntil { audioEngine.playbackRate == 0.25 })
        
        audioEngine.setPlaybackRate(3.0) // Very fast
        #expect(await waitUntil { audioEngine.playbackRate == 3.0 })
        
        // Invalid rates are ignored rather than forwarded to AVPlayer.
        audioEngine.setPlaybackRate(-1.0) // Negative rate
        audioEngine.setPlaybackRate(0.0) // Zero rate
        await Task.yield()
        #expect(audioEngine.playbackRate == 3.0)
    }
    
    // MARK: - Memory Management Tests
    
    @Test("AudioEngine should handle multiple load operations")
    func audioEngineMultipleLoadOperations() async throws {
        let audioEngine = AudioEngine()
        
        // Load first file
        let audioURL1 = TestDataFactory.createMockAudioFile(named: "test1", duration: 1800)
        audioEngine.loadAudio(url: audioURL1)
        #expect(await waitUntil {
            (audioEngine.playerItem?.asset as? AVURLAsset)?.url == audioURL1
        })
        
        // Load second file (should replace first)
        let audioURL2 = TestDataFactory.createMockAudioFile(named: "test2", duration: 3600)
        audioEngine.loadAudio(url: audioURL2)
        #expect(await waitUntil {
            (audioEngine.playerItem?.asset as? AVURLAsset)?.url == audioURL2
        })
        
        // Should still be in valid state
        #expect(audioEngine.isPlaying == false)
        #expect(audioEngine.currentTime == 0)
    }
    
    @Test("AudioEngine should cleanup properly after multiple operations")
    func audioEngineCleanupAfterOperations() async throws {
        var audioEngine: AudioEngine? = AudioEngine()
        weak var weakEngine = audioEngine
        
        audioEngine?.loadAudio(url: mockAudioURL)
        #expect(await waitUntil { audioEngine?.player != nil })
        
        audioEngine?.play()
        #expect(await waitUntil { audioEngine?.isPlaying == true })
        
        audioEngine?.pause()
        #expect(await waitUntil { audioEngine?.isPlaying == false })
        
        audioEngine?.seek(to: 500.0)
        #expect(await waitUntil {
            (audioEngine?.player?.currentTime().seconds ?? 0) >= 499
        })
        
        audioEngine = nil
        
        #expect(await waitUntil { weakEngine == nil })
    }
    
    // MARK: - Thread Safety Tests
    
    @Test("AudioEngine should handle concurrent operations")
    func audioEngineConcurrentOperations() async throws {
        let audioEngine = AudioEngine()
        audioEngine.loadAudio(url: mockAudioURL)
        
        #expect(await waitUntil { audioEngine.player != nil })
        
        // Simulate concurrent operations
        await withTaskGroup(of: Void.self) { group in
            // Concurrent playback toggles
            group.addTask {
                for _ in 0..<10 {
                    audioEngine.togglePlayback()
                    await Task.yield()
                }
            }
            
            // Concurrent seek operations
            group.addTask {
                for i in 0..<10 {
                    audioEngine.seek(to: Double(i * 60)) // Seek to different positions
                    await Task.yield()
                }
            }
            
            // Concurrent rate changes
            group.addTask {
                let rates: [Float] = [1.0, 1.25, 1.5, 1.0]
                for rate in rates {
                    audioEngine.setPlaybackRate(rate)
                    await Task.yield()
                }
            }
        }
        
        #expect(await waitUntil { audioEngine.playbackRate == 1.0 })
        
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
        
        #expect(await waitUntil { audioEngine.player != nil })
        
        audioEngine.play()
        #expect(await waitUntil { audioEngine.isPlaying })
        
        // Simulate audio interruption by manually calling the interruption handler
        let interruptionNotification = Notification(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
            ]
        )
        
        NotificationCenter.default.post(interruptionNotification)
        
        #expect(await waitUntil { !audioEngine.isPlaying })
    }
    
    // MARK: - Performance Tests
    
    @Test("AudioEngine should load audio quickly")
    func audioEngineLoadPerformance() async throws {
        let audioEngine = AudioEngine()
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        audioEngine.loadAudio(url: mockAudioURL)
        
        #expect(await waitUntil { audioEngine.player != nil })
        
        let loadTime = CFAbsoluteTimeGetCurrent() - startTime
        
        // Should load within reasonable time (allowing for async operations)
        #expect(loadTime < TestConfiguration.maxAcceptableLoadTime)
    }
    
    // MARK: - State Consistency Tests
    
    @Test("AudioEngine should maintain consistent state during rapid operations")
    func audioEngineStateConsistency() async throws {
        let audioEngine = AudioEngine()
        audioEngine.loadAudio(url: mockAudioURL)
        
        #expect(await waitUntil { audioEngine.player != nil })
        
        // Rapid state changes
        for _ in 0..<20 {
            audioEngine.play()
            #expect(await waitUntil { audioEngine.isPlaying })
            
            audioEngine.pause()
            #expect(await waitUntil { !audioEngine.isPlaying })
        }
        
        // Final state should be consistent
        #expect(audioEngine.isPlaying == false)
        #expect(audioEngine.currentTime >= 0)
        #expect(audioEngine.duration >= 0)
    }
    
    // Note: Cleanup is handled by individual test methods and TestDataFactory as needed
}
