import Foundation
import SwiftUI

class GlobalAudioManager: ObservableObject, AudioManagerProtocol {
    static let shared = GlobalAudioManager()
    
    @Published var currentAudiobook: Audiobook?
    @Published var audioEngine: AudioEngine?
    @Published var multiFileAudioEngine: MultiFileAudioEngine?
    @Published var useMultiFileEngine = false
    @Published var isLoading = false
    @Published var isReady = false
    @Published var showMiniPlayer = false
    @Published var playbackState: PlaybackState = .stopped
    
    enum PlaybackState {
        case stopped
        case loading
        case playing
        case paused
        case failed
    }
    
    private init() {
        // Removed all initialization work to speed up app launch
        // Audio session setup is now deferred until first audio load
    }
    
    deinit {
        // Ensure proper cleanup when GlobalAudioManager is deallocated
        cleanupEngines()
        print("🧹 GlobalAudioManager: Deallocated and cleaned up")
    }
    
    func loadAudiobook(_ audiobook: Audiobook) {
        // If we're already playing this audiobook, don't reload
        if let current = currentAudiobook,
           current.objectID == audiobook.objectID,
           (audioEngine != nil || multiFileAudioEngine != nil) {
            print("🎵 GlobalAudioManager: Already loaded \(audiobook.title ?? "Unknown")")
            showMiniPlayer = true
            playbackState = isPlaying() ? .playing : .paused
            return
        }
        
        print("🎵 GlobalAudioManager: Loading audiobook: \(audiobook.title ?? "Unknown")")
        DispatchQueue.main.async {
            self.currentAudiobook = audiobook
            self.showMiniPlayer = false
            self.isLoading = true
            self.isReady = false
            self.playbackState = .loading
        }
        
        // Clean up existing engines
        cleanupEngines()
        
        guard let filePath = audiobook.fileURL, !filePath.isEmpty else {
            print("❌ GlobalAudioManager: No file path found")
            DispatchQueue.main.async {
                self.isLoading = false
                self.playbackState = .failed
            }
            return
        }
        
        // Perform file system checks and loading on background queue
        DispatchQueue.global(qos: .userInitiated).async {
            // Check if it's a folder (multi-file audiobook) or single file
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: filePath, isDirectory: &isDirectory) else {
                print("❌ GlobalAudioManager: File/folder not found at path: \(filePath)")
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.playbackState = .failed
                }
                return
            }
            
            DispatchQueue.main.async {
                if isDirectory.boolValue {
                    print("📁 GlobalAudioManager: Loading multi-file audiobook")
                    self.useMultiFileEngine = true
                    self.loadMultiFileAudiobook(audiobook, filePath: filePath)
                } else {
                    print("📄 GlobalAudioManager: Loading single audio file")
                    self.useMultiFileEngine = false
                    self.loadSingleFileAudiobook(audiobook, filePath: filePath)
                }
            }
        }
    }
    
    private func loadMultiFileAudiobook(_ audiobook: Audiobook, filePath: String) {
        // Create engine asynchronously
        DispatchQueue.global(qos: .userInitiated).async {
            let engine = MultiFileAudioEngine()
            engine.loadMultiFileAudiobook(audiobook)
            
            DispatchQueue.main.async {
                self.multiFileAudioEngine = engine
                
                // Resume from last position if needed
                if audiobook.currentPosition > 0 {
                    self.multiFileAudioEngine?.seek(to: audiobook.currentPosition)
                }
                self.isLoading = false
                self.isReady = true
                self.playbackState = .paused
            }
        }
    }
    
    private func loadSingleFileAudiobook(_ audiobook: Audiobook, filePath: String) {
        // Create engine asynchronously
        DispatchQueue.global(qos: .userInitiated).async {
            let engine = AudioEngine()
            let fileURL = URL(fileURLWithPath: filePath)
            engine.loadAudio(url: fileURL)
            
            DispatchQueue.main.async {
                self.audioEngine = engine
                
                // Resume from last position if needed
                if audiobook.currentPosition > 0 {
                    self.audioEngine?.seek(to: audiobook.currentPosition)
                }
                self.isLoading = false
                self.isReady = true
                self.playbackState = .paused
            }
        }
    }
    
    private func cleanupEngines() {
        // Properly cleanup audio engine with its cleanup method
        if audioEngine != nil {
            // AudioEngine has its own cleanup method that handles observers and time observer
            audioEngine = nil
            print("🧹 GlobalAudioManager: Cleaned up single-file audio engine")
        }
        
        // Properly cleanup multi-file audio engine with its cleanup method  
        if multiFileAudioEngine != nil {
            // MultiFileAudioEngine has its own cleanup method that handles observers and time observer
            multiFileAudioEngine = nil
            print("🧹 GlobalAudioManager: Cleaned up multi-file audio engine")
        }
    }
    
    func pausePlayback() {
        if useMultiFileEngine {
            multiFileAudioEngine?.pause()
        } else {
            audioEngine?.pause()
        }
        playbackState = .paused
    }
    
    func resumePlayback() {
        if useMultiFileEngine {
            multiFileAudioEngine?.play()
        } else {
            audioEngine?.play()
        }
        showMiniPlayer = true
        playbackState = .playing
    }
    
    func startPlayback() {
        resumePlayback()
        showMiniPlayer = true
        playbackState = .playing
    }
    
    func stopPlayback() {
        pausePlayback()
        showMiniPlayer = false
        playbackState = .stopped
    }
    
    func isPlaying() -> Bool {
        if useMultiFileEngine {
            return multiFileAudioEngine?.isPlaying ?? false
        } else {
            return audioEngine?.isPlaying ?? false
        }
    }
    
    func getCurrentTime() -> TimeInterval {
        if useMultiFileEngine {
            return multiFileAudioEngine?.currentTime ?? 0
        } else {
            return audioEngine?.currentTime ?? 0
        }
    }
    
    func getDuration() -> TimeInterval {
        if useMultiFileEngine {
            return multiFileAudioEngine?.duration ?? 0
        } else {
            return audioEngine?.duration ?? 0
        }
    }
    
    func getPlaybackRate() -> Float {
        if useMultiFileEngine {
            return multiFileAudioEngine?.playbackRate ?? 1.0
        } else {
            return audioEngine?.playbackRate ?? 1.0
        }
    }
    
    func setPlaybackRate(_ rate: Float) {
        print(rate)
        if useMultiFileEngine {
            multiFileAudioEngine?.setPlaybackRate(rate)
        } else {
            audioEngine?.setPlaybackRate(rate)
        }
    }
    
    func skipForward(_ interval: TimeInterval) {
        if useMultiFileEngine {
            multiFileAudioEngine?.skipForward(interval)
        } else {
            audioEngine?.skipForward(interval)
        }
    }
    
    func skipBackward(_ interval: TimeInterval) {
        if useMultiFileEngine {
            multiFileAudioEngine?.skipBackward(interval)
        } else {
            audioEngine?.skipBackward(interval)
        }
    }
    
    func togglePlayback() {
        let wasPlaying = isPlaying()
        
        if useMultiFileEngine {
            multiFileAudioEngine?.togglePlayback()
        } else {
            audioEngine?.togglePlayback()
        }
        
        // Update state based on toggle result
        if wasPlaying {
            playbackState = .paused
        } else {
            playbackState = .playing
            showMiniPlayer = true
        }
    }
    
    func seek(to time: TimeInterval) {
        if useMultiFileEngine {
            multiFileAudioEngine?.seek(to: time)
        } else {
            audioEngine?.seek(to: time)
        }
    }

    
    // MARK: - Enhanced Audio Processing Controls
    func enableNoiseSuppression(_ enabled: Bool) {
        if useMultiFileEngine {
            multiFileAudioEngine?.enableNoiseSuppression(enabled)
        } else {
            audioEngine?.enableNoiseSuppression(enabled)
        }
    }
    
    func setEqualizer(bassBoost: Float, trebleBoost: Float) {
        if useMultiFileEngine {
            multiFileAudioEngine?.setEqualizer(bassBoost: bassBoost, trebleBoost: trebleBoost)
        } else {
            audioEngine?.setEqualizer(bassBoost: bassBoost, trebleBoost: trebleBoost)
        }
    }
    
    func enableSpeechEnhancement(_ enabled: Bool) {
        if useMultiFileEngine {
            multiFileAudioEngine?.enableSpeechEnhancement(enabled)
        } else {
            audioEngine?.enableSpeechEnhancement(enabled)
        }
    }
    
    func enableDynamicRangeCompression(_ enabled: Bool, threshold: Float = -12.0, ratio: Float = 4.0) {
        if useMultiFileEngine {
            multiFileAudioEngine?.enableDynamicRangeCompression(enabled, threshold: threshold, ratio: ratio)
        }
        // Note: Single file engine doesn't have this method yet, but could be added similarly
    }
}
