import Foundation
import SwiftUI
import ActivityKit
import Combine

// MARK: - Playback controls, Live Activity, helpers
extension GlobalAudioManager {
    func pausePlayback() {
        if useMultiFileEngine {
            multiFileAudioEngine?.pause()
        } else {
            audioEngine?.pause()
        }
        playbackState = .paused
        NowPlayingSharedStore.write(
            audiobook: currentAudiobook,
            isPlaying: playbackState == .playing,
            currentTime: getCurrentTime(),
            duration: getDuration(),
            coverImageData: currentAudiobook?.coverImageData
        )
        updateLiveActivity()
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
        NowPlayingSharedStore.write(
            audiobook: currentAudiobook,
            isPlaying: playbackState == .playing,
            currentTime: getCurrentTime(),
            duration: getDuration(),
            coverImageData: currentAudiobook?.coverImageData
        )
        updateLiveActivity()
    }
    
    func startPlayback() {
        guard audioEngine != nil || multiFileAudioEngine != nil else {
            if isLoading { pendingAutoplay = true }
            return
        }
        resumePlayback()
        showMiniPlayer = true
        playbackState = .playing
        NowPlayingSharedStore.write(
            audiobook: currentAudiobook,
            isPlaying: playbackState == .playing,
            currentTime: getCurrentTime(),
            duration: getDuration(),
            coverImageData: currentAudiobook?.coverImageData
        )
        updateLiveActivity()
    }
    
    func stopPlayback() {
        pendingAutoplay = false
        pausePlayback()
        showMiniPlayer = false
        playbackState = .stopped
        NowPlayingSharedStore.write(
            audiobook: currentAudiobook,
            isPlaying: playbackState == .playing,
            currentTime: getCurrentTime(),
            duration: getDuration(),
            coverImageData: currentAudiobook?.coverImageData
        )
        updateLiveActivity()
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
        NowPlayingSharedStore.write(
            audiobook: currentAudiobook,
            isPlaying: playbackState == .playing,
            currentTime: getCurrentTime(),
            duration: getDuration(),
            coverImageData: currentAudiobook?.coverImageData
        )
        updateLiveActivity()
    }
    
    func skipForward(_ interval: TimeInterval) {
        if useMultiFileEngine {
            multiFileAudioEngine?.skipForward(interval)
        } else {
            audioEngine?.skipForward(interval)
        }
        NowPlayingSharedStore.write(
            audiobook: currentAudiobook,
            isPlaying: playbackState == .playing,
            currentTime: getCurrentTime(),
            duration: getDuration(),
            coverImageData: currentAudiobook?.coverImageData
        )
        updateLiveActivity()
    }
    
    func skipBackward(_ interval: TimeInterval) {
        if useMultiFileEngine {
            multiFileAudioEngine?.skipBackward(interval)
        } else {
            audioEngine?.skipBackward(interval)
        }
        NowPlayingSharedStore.write(
            audiobook: currentAudiobook,
            isPlaying: playbackState == .playing,
            currentTime: getCurrentTime(),
            duration: getDuration(),
            coverImageData: currentAudiobook?.coverImageData
        )
        updateLiveActivity()
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
        NowPlayingSharedStore.write(
            audiobook: currentAudiobook,
            isPlaying: playbackState == .playing,
            currentTime: getCurrentTime(),
            duration: getDuration(),
            coverImageData: currentAudiobook?.coverImageData
        )
        updateLiveActivity()
    }
    
    func seek(to time: TimeInterval) {
        if useMultiFileEngine {
            multiFileAudioEngine?.seek(to: time)
        } else {
            audioEngine?.seek(to: time)
        }
        NowPlayingSharedStore.write(
            audiobook: currentAudiobook,
            isPlaying: playbackState == .playing,
            currentTime: getCurrentTime(),
            duration: getDuration(),
            coverImageData: currentAudiobook?.coverImageData
        )
        updateLiveActivity()
    }

    
    // MARK: - Enhanced Audio Processing Controls
    func enableDynamicRangeCompression(_ enabled: Bool, threshold: Float = -12.0, ratio: Float = 4.0) {
        if useMultiFileEngine {
            multiFileAudioEngine?.enableDynamicRangeCompression(enabled, threshold: threshold, ratio: ratio)
        }
        // Note: Single file engine doesn't have this method yet, but could be added similarly
    }
    
    // MARK: - Live Activity Management
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
        updateLiveActivity()
    }

    private func updateLiveActivity() {
        guard let audiobook = currentAudiobook else {
            liveActivityManager.endLiveActivity()
            return
        }
        
        let contentState = AudiobookLiveActivityAttributes.ContentState(
            title: audiobook.title ?? "Unknown Title",
            author: audiobook.author ?? "Unknown Author",
            chapterTitle: audiobook.chapters.first?.title,
            currentTime: getCurrentTime(),
            duration: getDuration(),
            isPlaying: playbackState == .playing,
            playbackRate: getPlaybackRate(),
            updatedAt: Date()
        )
        
        // Start live activity if not already started, otherwise update
        if playbackState == .playing && !liveActivityManager.isActivityActive {
            liveActivityManager.startLiveActivity(
                for: contentState,
                audiobookId: audiobook.id.uuidString
            )
        } else if liveActivityManager.isActivityActive {
            liveActivityManager.updateLiveActivity(with: contentState)
        }
        
        // End live activity when stopped
        if playbackState == .stopped {
            liveActivityManager.endLiveActivity()
        }
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
