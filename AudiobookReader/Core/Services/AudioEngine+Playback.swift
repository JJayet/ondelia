import Foundation
import AVFoundation
import MediaPlayer

extension AudioEngine {
    // MARK: - Cleanup
    func cleanup() {
        // Prevent multiple cleanup calls
        guard !isCleanedUp else { 
            Log.audio.warning("⚠️ AudioEngine: Cleanup already performed")
            return 
        }
        isCleanedUp = true
        
        Log.audio.debug("🧹 AudioEngine: Starting cleanup...")
        
        // Stop playback first on current thread
        player?.pause()

        // Remove time observer from current player synchronously
        if let observer = timeObserver, let currentPlayer = player {
            currentPlayer.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        // Remove KVO observers synchronously if they were added
        if hasAddedObservers, let item = playerItem {
            item.removeObserver(self, forKeyPath: "duration")
            item.removeObserver(self, forKeyPath: "status")
            hasAddedObservers = false
        }
        
        // Clear references synchronously
        player = nil
        playerItem = nil
        
        // Only called from deinit: never block on main here; skip the observable write off-main
        if Thread.isMainThread {
            isPlaying = false
        }

        Log.audio.debug("✅ AudioEngine: Cleanup completed")
    }

    private func cleanupPlayerDirectly() {
        // This method runs on audioQueue, so no need for sync
        // Remove time observer from current player
        if let observer = timeObserver, let currentPlayer = player {
            currentPlayer.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        // Remove KVO observers if they were added
        if hasAddedObservers, let item = playerItem {
            item.removeObserver(self, forKeyPath: "duration")
            item.removeObserver(self, forKeyPath: "status")
            hasAddedObservers = false
        }
        
        // Clear references
        player = nil
        playerItem = nil
        
        DispatchQueue.main.async { [weak self] in
            self?.isPlaying = false
        }
    }

    // MARK: - Load Audio File
    func loadAudio(url: URL) {
        Log.audio.debug("AudioEngine: Loading audio from URL: \(url)")
        Log.audio.debug("AudioEngine: File exists: \(FileManager.default.fileExists(atPath: url.path))")

        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
            DispatchQueue.main.async { [weak self] in
                self?.isPlaying = false
                self?.currentTime = 0
                self?.duration = 0
            }
            return
        }
        
        // Setup audio session once; flag is set inside on success so failures retry next load
        if !hasSetupAudioSession {
            setupAudioSession()
        }
        
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Clean up existing player directly without calling cleanup() to avoid deadlock
            self.cleanupPlayerDirectly()
            
            let asset = AVURLAsset(url: url)
            let newPlayerItem = AVPlayerItem(asset: asset)
            let newPlayer = AVPlayer(playerItem: newPlayerItem)
            
            self.player = newPlayer
            self.playerItem = newPlayerItem
            
            // Add time observer with optimized interval for better performance
            let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            self.timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                self?.updateCurrentTime(time.seconds)
            }
            
            // Observe duration and status
            newPlayerItem.addObserver(self, forKeyPath: "duration", options: [.new, .initial], context: nil)
            newPlayerItem.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
            self.hasAddedObservers = true
            
            // Setup now playing info asynchronously to avoid blocking
            DispatchQueue.global(qos: .utility).async {
                self.setupNowPlayingInfo(asset: asset)
            }
        }
    }
    
    // MARK: - Playback Controls
    func play() {
        audioQueue.async { [weak self] in
            guard let self = self, let player = self.player else { return }
            
            player.play()
            
            DispatchQueue.main.async {
                self.isPlaying = true
                self.updateNowPlayingInfo()
            }
        }
    }
    
    func pause() {
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.player?.pause()
            
            DispatchQueue.main.async {
                self.isPlaying = false
                self.updateNowPlayingInfo()
            }
        }
    }
    
    func togglePlayback() {
        stateQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.isPlaying {
                self.pause()
            } else {
                self.play()
            }
        }
    }
    
    func seek(to time: TimeInterval) {
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            
            let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            self.player?.seek(to: cmTime)
            
            DispatchQueue.main.async {
                self.updateNowPlayingInfo()
            }
        }
    }
    
    func skipForward(_ seconds: TimeInterval = 15) {
        stateQueue.async { [weak self] in
            guard let self = self else { return }
            
            let newTime = self.currentTime + seconds
            self.seek(to: min(newTime, self.duration))
        }
    }
    
    func skipBackward(_ seconds: TimeInterval = 15) {
        stateQueue.async { [weak self] in
            guard let self = self else { return }
            
            let newTime = self.currentTime - seconds
            self.seek(to: max(newTime, 0))
        }
    }
    
    func setPlaybackRate(_ rate: Float) {
        guard rate.isFinite, rate > 0 else { return }
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.playbackRate = rate
            
            if self.isPlaying {
                self.player?.rate = rate
            }
            
            DispatchQueue.main.async {
                self.updateNowPlayingInfo()
            }
        }
    }
}
