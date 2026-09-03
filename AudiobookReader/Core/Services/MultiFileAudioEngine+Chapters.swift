import Foundation
import AVFoundation
import MediaPlayer

extension MultiFileAudioEngine {
    // MARK: - Chapter Management
    func switchToChapter(_ chapterIndex: Int) {
        // This method is called from playerQueue, so it's already thread-safe
        guard chapterIndex >= 0 && chapterIndex < chapterFiles.count else { return }
        
        // Clean up current player's time observer first
        if let observer = timeObserver, let currentPlayer = players[currentPlayerIndex] {
            currentPlayer.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        // Pause current player
        if let currentPlayer = players[currentPlayerIndex] {
            currentPlayer.pause()
        }
        
        // Update indices; @Published write goes to main
        currentPlayerIndex = chapterIndex
        DispatchQueue.main.async { [weak self] in
            self?.currentChapterIndex = chapterIndex
        }

        // Load the new chapter if not already loaded
        loadChapterPlayer(chapterIndex)
        
        // Set up time observer for the new player
        setupTimeObserver()
        
        // Preload adjacent chapters and unload distant ones
        preloadAdjacentChapters()
        unloadDistantChapters()
        
        print("📖 MultiFileAudioEngine: Switched to chapter \(chapterIndex + 1)")
    }
    
    func findChapterIndex(for time: TimeInterval) -> Int {
        for (index, chapter) in chapters.enumerated() {
            if time >= chapter.startTime && time < chapter.endTime {
                return index
            }
        }
        
        // If not found, return the last chapter or 0
        return max(0, chapters.count - 1)
    }
    
    // MARK: - Time Observer
    func setupTimeObserver() {
        // Use a longer interval for better performance - UI will be updated by the PlayerView timer
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        
        // Remove existing observer
        if let observer = timeObserver {
            for player in players.values {
                player.removeTimeObserver(observer)
            }
        }
        
        // Add observer to current player
        if let currentPlayer = players[currentPlayerIndex] {
            timeObserver = currentPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                self?.updateCurrentTime(time)
            }
        }
    }
    
    private func updateCurrentTime(_ time: CMTime) {
        // This method is already called on the main queue from the time observer
        guard !isTransitioning else { return }
        
        let currentChapterTime = time.seconds
        let chapter = chapters[safe: currentPlayerIndex]
        let chapterStartTime = chapter?.startTime ?? 0
        
        currentTime = chapterStartTime + currentChapterTime
        
        // Check if we need to transition to the next chapter
        if let currentChapter = chapter,
           currentChapterTime >= currentChapter.endTime - currentChapter.startTime - 0.1 { // 0.1 second buffer
            // Perform chapter transition on player queue to avoid blocking UI
            playerQueue.async { [weak self] in
                self?.safeTransitionToNextChapter()
            }
        }
    }
    
    private func transitionToNextChapter() {
        guard !isTransitioning,
              currentPlayerIndex < chapterFiles.count - 1 else { return }
        
        // Set transitioning flag atomically
        isTransitioning = true
        
        let nextChapterIndex = currentPlayerIndex + 1
        
        print("🔄 MultiFileAudioEngine: Transitioning to chapter \(nextChapterIndex + 1)")
        
        // Step 1: Clean up current player's time observer
        if let observer = timeObserver, 
           let currentPlayer = players[currentPlayerIndex] {
            currentPlayer.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        // Step 2: Pause current player
        if let currentPlayer = players[currentPlayerIndex] {
            currentPlayer.pause()
        }
        
        // Step 3: Switch to next chapter; @Published write goes to main
        currentPlayerIndex = nextChapterIndex
        DispatchQueue.main.async { [weak self] in
            self?.currentChapterIndex = nextChapterIndex
        }
        
        // Step 4: Load the new chapter if not already loaded
        loadChapterPlayer(nextChapterIndex)
        
        // Step 5: Set up time observer for new player
        setupTimeObserver()
        
        // Step 6: Resume playback if we were playing and notify UI on main queue
        if isPlaying {
            if let newPlayer = players[nextChapterIndex] {
                newPlayer.rate = playbackRate
                newPlayer.play()
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, !self.isCleanedUp else { return }
                    self.updateNowPlayingInfo()
                }
            }
        }
        
        // Step 7: Manage memory efficiently
        preloadAdjacentChapters()
        unloadDistantChapters()
        
        // Step 8: Reset transitioning flag
        isTransitioning = false
    }

    // MARK: - Safety Mechanisms
    private func validatePlayerState() -> Bool {
        // Ensure current indices are within bounds
        guard currentPlayerIndex >= 0 && currentPlayerIndex < chapterFiles.count else {
            print("⚠️ MultiFileAudioEngine: Invalid currentPlayerIndex: \(currentPlayerIndex), resetting to 0")
            currentPlayerIndex = 0
            DispatchQueue.main.async { [weak self] in self?.currentChapterIndex = 0 }
            return false
        }

        guard currentChapterIndex >= 0 && currentChapterIndex < chapters.count else {
            print("⚠️ MultiFileAudioEngine: Invalid currentChapterIndex: \(currentChapterIndex), resetting to 0")
            DispatchQueue.main.async { [weak self] in self?.currentChapterIndex = 0 }
            return false
        }
        
        return true
    }
    
    private func safeTransitionToNextChapter() {
        guard validatePlayerState() else { return }
        transitionToNextChapter()
    }
}
