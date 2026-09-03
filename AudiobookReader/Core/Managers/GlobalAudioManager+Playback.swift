import Foundation
import SwiftUI

// MARK: - Playback controls, Live Activity, helpers
extension GlobalAudioManager {
    func pausePlayback() {
        if useMultiFileEngine {
            multiFileAudioEngine?.pause()
        } else {
            audioEngine?.pause()
        }
        playbackState = .paused
        playbackStateDidChange()
    }
    
    func resumePlayback() {
        guard audioEngine != nil || multiFileAudioEngine != nil else {
            if isLoading { pendingAutoplay = true }
            return
        }
        if useMultiFileEngine {
            multiFileAudioEngine?.play()
        } else {
            audioEngine?.play()
        }
        showMiniPlayer = true
        playbackState = .playing
        playbackStateDidChange()
    }
    
    func startPlayback() {
        guard audioEngine != nil || multiFileAudioEngine != nil else {
            if isLoading { pendingAutoplay = true }
            return
        }
        resumePlayback()
        showMiniPlayer = true
        playbackState = .playing
        playbackStateDidChange()
    }
    
    func stopPlayback() {
        pendingAutoplay = false
        pausePlayback()
        showMiniPlayer = false
        playbackState = .stopped
        playbackStateDidChange()
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
        rememberSpeed(rate)
        if useMultiFileEngine {
            multiFileAudioEngine?.setPlaybackRate(rate)
        } else {
            audioEngine?.setPlaybackRate(rate)
        }
        playbackStateDidChange()
    }
    
    func skipForward(_ interval: TimeInterval) {
        if useMultiFileEngine {
            multiFileAudioEngine?.skipForward(interval)
        } else {
            audioEngine?.skipForward(interval)
        }
        playbackStateDidChange()
    }
    
    func skipBackward(_ interval: TimeInterval) {
        if useMultiFileEngine {
            multiFileAudioEngine?.skipBackward(interval)
        } else {
            audioEngine?.skipBackward(interval)
        }
        playbackStateDidChange()
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
        playbackStateDidChange()
    }
    
    func seek(to time: TimeInterval) {
        if useMultiFileEngine {
            multiFileAudioEngine?.seek(to: time)
        } else {
            audioEngine?.seek(to: time)
        }
        // A deliberate jump is worth writing straight away rather than waiting for the save timer.
        persistProgress()
        playbackStateDidChange()
    }

    
    // MARK: - Enhanced Audio Processing Controls
    func enableDynamicRangeCompression(_ enabled: Bool, threshold: Float = -12.0, ratio: Float = 4.0) {
        if useMultiFileEngine {
            multiFileAudioEngine?.enableDynamicRangeCompression(enabled, threshold: threshold, ratio: ratio)
        }
        // Note: Single file engine doesn't have this method yet, but could be added similarly
    }
    
    // MARK: - Now Playing Snapshot
    func publishPlaybackSnapshot(reloadTimeline: Bool = false) {
        NowPlayingSharedStore.write(
            audiobook: currentAudiobook,
            isPlaying: playbackState == .playing,
            currentTime: getCurrentTime(),
            duration: getDuration(),
            coverImageData: currentAudiobook?.coverImageData,
            playbackRate: getPlaybackRate(),
            reloadTimeline: reloadTimeline
        )
    }

    // MARK: - Utility Functions
    func formatTime(_ time: TimeInterval) -> String {
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
