import Foundation
import SwiftUI

@MainActor
class GlobalAudioManager: ObservableObject, AudioManagerProtocol {
    static let shared = GlobalAudioManager()
    
    @Published var currentAudiobook: AudiobookModel?
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
    
    func loadAudiobook(_ audiobook: AudiobookModel) {
        // If we're already playing this audiobook, don't reload
        if let current = currentAudiobook,
           current.id == audiobook.id,
           (audioEngine != nil || multiFileAudioEngine != nil) {
            print("🎵 GlobalAudioManager: Already loaded \(audiobook.title ?? "Unknown")")
            showMiniPlayer = true
            playbackState = isPlaying() ? .playing : .paused
            return
        }
        
        print("🎵 GlobalAudioManager: Loading audiobook: \(audiobook.title ?? "Unknown")")
        
        // Save current playback position before switching
        if let current = currentAudiobook, (audioEngine != nil || multiFileAudioEngine != nil) {
            let currentTime = getCurrentTime()
            print("💾 GlobalAudioManager: Saving position \(formatTime(currentTime)) for \(current.title ?? "Unknown")")
            // Save to Core Data or user defaults here if needed
        }
        
        // Stop current playback immediately to prevent audio conflicts
        if isPlaying() {
            pausePlayback()
        }
        
        self.currentAudiobook = audiobook
        self.showMiniPlayer = false
        self.isLoading = true
        self.isReady = false
        self.playbackState = .loading
        
        // Clean up existing engines immediately to prevent conflicts
        cleanupEngines()
        
        guard let filePath = audiobook.fileURL, !filePath.isEmpty else {
            print("❌ GlobalAudioManager: No file path found")
            self.isLoading = false
            self.playbackState = .failed
            return
        }
        
        // Move file operations to background thread to avoid blocking main thread
        Task {
            let fileOperationResult = await performFileOperations(filePath: filePath)
            
            await MainActor.run {
                switch fileOperationResult {
                case .success(let isDirectory):
                    if isDirectory {
                        print("📁 GlobalAudioManager: Loading multi-file audiobook")
                        self.useMultiFileEngine = true
                        self.loadMultiFileAudiobook(audiobook, filePath: filePath)
                    } else {
                        print("📄 GlobalAudioManager: Loading single audio file")
                        self.useMultiFileEngine = false
                        self.loadSingleFileAudiobook(audiobook, filePath: filePath)
                    }
                case .failure(let error):
                    print("❌ GlobalAudioManager: File error: \(error)")
                    self.isLoading = false
                    self.playbackState = .failed
                }
            }
        }
    }

    private func performFileOperations(filePath: String) async -> Result<Bool, Error> {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Perform file operations on background thread
                var isDirectory: ObjCBool = false
                let fileExists = FileManager.default.fileExists(atPath: filePath, isDirectory: &isDirectory)
                
                if fileExists {
                    continuation.resume(returning: .success(isDirectory.boolValue))
                } else {
                    let error = NSError(domain: "AudiobookReader", code: 404, userInfo: [NSLocalizedDescriptionKey: "File/folder not found at path: \(filePath)"])
                    continuation.resume(returning: .failure(error))
                }
            }
        }
    }
    
    private func loadMultiFileAudiobook(_ audiobook: AudiobookModel, filePath: String) {
        // Create engine on main thread and assign immediately to retain it
        let engine = MultiFileAudioEngine()
        self.multiFileAudioEngine = engine
        
        // Load audio (engine handles its own threading)
        engine.loadMultiFileAudiobook(audiobook)
        // Resume from last position if needed
        if audiobook.currentPosition > 0 {
            self.multiFileAudioEngine?.seek(to: audiobook.currentPosition)
        }
        self.isLoading = false
        self.isReady = true
        self.playbackState = .paused
    }
    
    private func loadSingleFileAudiobook(_ audiobook: AudiobookModel, filePath: String) {
        // Create engine on main thread and assign immediately to retain it
        let engine = AudioEngine()
        self.audioEngine = engine
        
        let fileURL = URL(fileURLWithPath: filePath)
        engine.loadAudio(url: fileURL)
        if audiobook.currentPosition > 0 {
            self.audioEngine?.seek(to: audiobook.currentPosition)
        }
        self.isLoading = false
        self.isReady = true
        self.playbackState = .paused
    }
    
    private func cleanupEngines() {
        print("🧹 GlobalAudioManager: Starting engine cleanup...")
        
        // Store strong references to ensure cleanup completes before deallocation
        let currentAudioEngine = audioEngine
        let currentMultiFileEngine = multiFileAudioEngine
        
        // Clear the published properties immediately to prevent new operations
        audioEngine = nil
        multiFileAudioEngine = nil
        
        // Stop any ongoing playback synchronously
        if let engine = currentAudioEngine, engine.isPlaying {
            engine.pause()
        }
        if let engine = currentMultiFileEngine, engine.isPlaying {
            engine.pause()
        }
        
        // Cleanup engines synchronously to prevent weak reference issues
        // The engines' deinit will handle the actual cleanup when references are released
        print("✅ GlobalAudioManager: Engine cleanup completed (engines will deinit naturally)")
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
    
    // MARK: - Utility Functions
    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
