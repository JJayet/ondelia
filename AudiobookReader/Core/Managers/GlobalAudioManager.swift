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
    
    private init() {}
    
    func loadAudiobook(_ audiobook: Audiobook) {
        // If we're already playing this audiobook, don't reload
        if let current = currentAudiobook,
           current.objectID == audiobook.objectID,
           (audioEngine != nil || multiFileAudioEngine != nil) {
            print("🎵 GlobalAudioManager: Already loaded \(audiobook.title ?? "Unknown")")
            return
        }
        
        print("🎵 GlobalAudioManager: Loading audiobook: \(audiobook.title ?? "Unknown")")
        currentAudiobook = audiobook
        
        // Clean up existing engines
        audioEngine = nil
        multiFileAudioEngine = nil
        
        guard let filePath = audiobook.fileURL, !filePath.isEmpty else {
            print("❌ GlobalAudioManager: No file path found")
            return
        }
        
        // Check if it's a folder (multi-file audiobook) or single file
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: filePath, isDirectory: &isDirectory) else {
            print("❌ GlobalAudioManager: File/folder not found at path: \(filePath)")
            return
        }
        
        if isDirectory.boolValue {
            print("📁 GlobalAudioManager: Loading multi-file audiobook")
            useMultiFileEngine = true
            multiFileAudioEngine = MultiFileAudioEngine()
            multiFileAudioEngine?.loadMultiFileAudiobook(audiobook)
            
            // Resume from last position
            if audiobook.currentPosition > 0 {
                multiFileAudioEngine?.seek(to: audiobook.currentPosition)
            }
        } else {
            print("📄 GlobalAudioManager: Loading single audio file")
            useMultiFileEngine = false
            audioEngine = AudioEngine()
            let fileURL = URL(fileURLWithPath: filePath)
            audioEngine?.loadAudio(url: fileURL)
            
            // Resume from last position
            if audiobook.currentPosition > 0 {
                audioEngine?.seek(to: audiobook.currentPosition)
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
}