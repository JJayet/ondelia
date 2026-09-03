import Foundation
import AVFoundation
import MediaPlayer

extension MultiFileAudioEngine {
    // MARK: - Playback Controls
    func play() {
        playerQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Ensure current chapter is loaded
            self.loadChapterPlayer(self.currentPlayerIndex)
            
            guard let currentPlayer = self.players[self.currentPlayerIndex] else { return }
            
            currentPlayer.rate = self.playbackRate
            currentPlayer.play()
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self, !self.isCleanedUp else { return }
                self.isPlaying = true
                self.updateNowPlayingInfo()
            }
            
            // Preload adjacent chapters and unload distant ones
            self.preloadAdjacentChapters()
            self.unloadDistantChapters()
            
            print("▶️ MultiFileAudioEngine: Playing chapter \(self.currentPlayerIndex + 1)")
        }
    }
    
    func pause() {
        playerQueue.async { [weak self] in
            guard let self = self else { return }
            
            for player in self.players.values {
                player.pause()
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self, !self.isCleanedUp else { return }
                self.isPlaying = false
                self.updateNowPlayingInfo()
            }
            
            print("⏸️ MultiFileAudioEngine: Paused")
        }
    }
    
    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func seek(to time: TimeInterval) {
        playerQueue.async { [weak self] in
            guard let self = self, !self.chapterFiles.isEmpty else { return }
            
            // Find which chapter this time belongs to
            let targetChapterIndex = self.findChapterIndex(for: time)
            let targetChapter = self.chapters[safe: targetChapterIndex]
            
            let chapterStartTime = targetChapter?.startTime ?? 0
            let timeWithinChapter = time - chapterStartTime
            
            // Switch to the correct chapter if needed
            if targetChapterIndex != self.currentPlayerIndex {
                self.switchToChapter(targetChapterIndex)
            }
            
            // Ensure the target chapter is loaded
            self.loadChapterPlayer(targetChapterIndex)
            
            // Seek within the current chapter
            guard let currentPlayer = self.players[self.currentPlayerIndex] else { return }
            let cmTime = CMTime(seconds: timeWithinChapter, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            currentPlayer.seek(to: cmTime)
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self, !self.isCleanedUp else { return }
                self.currentTime = time
                self.updateNowPlayingInfo()
            }
            
            print("⏭️ MultiFileAudioEngine: Seeked to \(self.formatTime(time)) (Chapter \(targetChapterIndex + 1))")
        }
    }
    
    func skipForward(_ seconds: TimeInterval = 15) {
        let newTime = currentTime + seconds
        seek(to: min(newTime, duration))
    }
    
    func skipBackward(_ seconds: TimeInterval = 15) {
        let newTime = currentTime - seconds
        seek(to: max(newTime, 0))
    }
    
    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying, let currentPlayer = players[currentPlayerIndex] {
            currentPlayer.rate = rate
        }
        updateNowPlayingInfo()
    }
}
