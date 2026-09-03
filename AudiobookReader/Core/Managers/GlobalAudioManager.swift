import Foundation
import SwiftUI

@MainActor
@Observable
final class GlobalAudioManager: AudioManagerProtocol {
    static let shared = GlobalAudioManager()
    
    var currentAudiobook: AudiobookModel?
    var audioEngine: AudioEngine?
    var multiFileAudioEngine: MultiFileAudioEngine?
    var useMultiFileEngine = false
    var isLoading = false
    var isReady = false
    var showMiniPlayer = false
    var playbackState: PlaybackState = .stopped
    var sleepTimeRemaining: TimeInterval = 0
    var sleepTimer: Timer?
    /// Writes the playback position to the library while a book plays. See `+Progress`.
    var progressTimer: Timer?
    var pendingAutoplay = false
    var loadRequestID = UUID()
    
    
    enum PlaybackState {
        case stopped
        case loading
        case playing
        case paused
        case failed
    }
    
    func loadAudiobook(_ audiobook: AudiobookModel) {
        // Do not start a second load for the same book while its engine is being prepared.
        if let current = currentAudiobook,
           current.id == audiobook.id,
           (isLoading || audioEngine != nil || multiFileAudioEngine != nil) {
            Log.audio.debug("🎵 GlobalAudioManager: Already loaded \(audiobook.title ?? "Unknown")")
            if !isLoading {
                showMiniPlayer = true
                playbackState = isPlaying() ? .playing : .paused
            }
            return
        }
        
        Log.audio.debug("🎵 GlobalAudioManager: Loading audiobook: \(audiobook.title ?? "Unknown")")
        // Save current playback position before switching
        if currentAudiobook != nil, audioEngine != nil || multiFileAudioEngine != nil {
            persistProgress()
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
        self.pendingAutoplay = false
        let requestID = UUID()
        self.loadRequestID = requestID
        
        // Clean up existing engines immediately to prevent conflicts
        cleanupEngines()
        
        guard let filePath = audiobook.resolvedFileURL?.path else {
            Log.audio.error("❌ GlobalAudioManager: No file path found")
            self.isLoading = false
            self.playbackState = .failed
            return
        }
        
        // Move file operations to background thread to avoid blocking main thread
        Task {
            let fileOperationResult = await performFileOperations(filePath: filePath)
            
            await MainActor.run {
                // Stale completion: another loadAudiobook ran meanwhile
                guard self.currentAudiobook?.id == audiobook.id,
                      self.loadRequestID == requestID else { return }
                switch fileOperationResult {
                case .success(let isDirectory):
                    if isDirectory {
                        Log.audio.debug("📁 GlobalAudioManager: Loading multi-file audiobook")
                        self.useMultiFileEngine = true
                        self.loadMultiFileAudiobook(audiobook, filePath: filePath)
                    } else {
                        Log.audio.debug("📄 GlobalAudioManager: Loading single audio file")
                        self.useMultiFileEngine = false
                        self.loadSingleFileAudiobook(audiobook, filePath: filePath)
                    }
                case .failure(let error):
                    Log.audio.error("❌ GlobalAudioManager: File error: \(error)")
                    self.isLoading = false
                    self.playbackState = .failed
                }
                NowPlayingSharedStore.write(
                    audiobook: self.currentAudiobook,
                    isPlaying: self.playbackState == .playing,
                    currentTime: self.getCurrentTime(),
                    duration: self.getDuration(),
                    coverImageData: self.currentAudiobook?.coverImageData
                )
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
        applyStoredSpeed(for: audiobook)
        self.isLoading = false
        self.isReady = true
        self.playbackState = .paused
        startPendingPlaybackIfNeeded()
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
        applyStoredSpeed(for: audiobook)
        self.isLoading = false
        self.isReady = true
        self.playbackState = .paused
        startPendingPlaybackIfNeeded()
    }

    private func startPendingPlaybackIfNeeded() {
        guard pendingAutoplay else { return }
        pendingAutoplay = false
        resumePlayback()
    }
    
    private func cleanupEngines() {
        Log.audio.debug("🧹 GlobalAudioManager: Starting engine cleanup...")
        
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
        Log.audio.debug("✅ GlobalAudioManager: Engine cleanup completed (engines will deinit naturally)")
    }
}
