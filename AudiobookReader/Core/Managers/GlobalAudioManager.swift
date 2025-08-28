import Foundation
import SwiftUI

class GlobalAudioManager: ObservableObject {
    static let shared = GlobalAudioManager()
    
    @Published var currentAudiobook: Audiobook?
    @Published var audioEngine: AudioEngine?
    @Published var multiFileAudioEngine: MultiFileAudioEngine?
    @Published var useMultiFileEngine = false
    @Published var isLoading = false
    @Published var isReady = false
    @Published var showMiniPlayer = false
    
    private init() {}
    
    func loadAudiobook(_ audiobook: Audiobook) {
        // If we're already playing this audiobook, don't reload
        if let current = currentAudiobook,
           current.objectID == audiobook.objectID,
           (audioEngine != nil || multiFileAudioEngine != nil) {
            print("🎵 GlobalAudioManager: Already loaded \(audiobook.title ?? "Unknown")")
            showMiniPlayer = true
            return
        }
        
        print("🎵 GlobalAudioManager: Loading audiobook: \(audiobook.title ?? "Unknown")")
        DispatchQueue.main.async {
            self.currentAudiobook = audiobook
            self.showMiniPlayer = false
            self.isLoading = true
            self.isReady = false
        }
        
        // Clean up existing engines
        audioEngine = nil
        multiFileAudioEngine = nil
        
        guard let filePath = audiobook.fileURL, !filePath.isEmpty else {
            print("❌ GlobalAudioManager: No file path found")
            DispatchQueue.main.async {
                self.isLoading = false
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
                }
                return
            }
            
            DispatchQueue.main.async {
                if isDirectory.boolValue {
                    print("📁 GlobalAudioManager: Loading multi-file audiobook")
                    self.useMultiFileEngine = true
                    self.multiFileAudioEngine = MultiFileAudioEngine()
                    
                    // Load the audiobook asynchronously
                    DispatchQueue.global(qos: .userInitiated).async {
                        self.multiFileAudioEngine?.loadMultiFileAudiobook(audiobook)
                        
                        DispatchQueue.main.async {
                            // Resume from last position
                            if audiobook.currentPosition > 0 {
                                self.multiFileAudioEngine?.seek(to: audiobook.currentPosition)
                            }
                            self.isLoading = false
                            self.isReady = true
                        }
                    }
                } else {
                    print("📄 GlobalAudioManager: Loading single audio file")
                    self.useMultiFileEngine = false
                    
                    // Load single file asynchronously
                    DispatchQueue.global(qos: .userInitiated).async {
                        let audioEngine = AudioEngine()
                        let fileURL = URL(fileURLWithPath: filePath)
                        audioEngine.loadAudio(url: fileURL)
                        
                        DispatchQueue.main.async {
                            self.audioEngine = audioEngine
                            
                            // Resume from last position
                            if audiobook.currentPosition > 0 {
                                self.audioEngine?.seek(to: audiobook.currentPosition)
                            }
                            self.isLoading = false
                            self.isReady = true
                        }
                    }
                }
            }
        }
    }
    
    func pausePlayback() {
        if useMultiFileEngine {
            multiFileAudioEngine?.pause()
        } else {
            audioEngine?.pause()
        }
    }
    
    func resumePlayback() {
        if useMultiFileEngine {
            multiFileAudioEngine?.play()
        } else {
            audioEngine?.play()
        }
        showMiniPlayer = true
    }
    
    func startPlayback() {
        resumePlayback()
        showMiniPlayer = true
    }
    
    func stopPlayback() {
        pausePlayback()
        showMiniPlayer = false
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
        if useMultiFileEngine {
            multiFileAudioEngine?.togglePlayback()
        } else {
            audioEngine?.togglePlayback()
        }
        
        // Update mini player visibility based on playback state
        if isPlaying() {
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
}