import Foundation
import AVFoundation
import MediaPlayer

@Observable
class MultiFileAudioEngine: NSObject {
    var players: [Int: AVPlayer] = [:] // Sparse array for lazy loading
    var playerItems: [Int: AVPlayerItem] = [:] // Sparse array for lazy loading
    var currentPlayerIndex = 0
    var timeObserver: Any?
    var chapters: [ChapterModel] = []
    var audiobook: AudiobookModel?
    var hasAddedObservers: Set<AVPlayerItem> = []
    var chapterFiles: [String] = [] // File paths for each chapter
    var folderURL: URL?
    var isCleanedUp = false
    var hasSetupAudioSession = false
    var remoteCommandTargets: [(MPRemoteCommand, Any)] = []

    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var playbackRate: Float = 1.0
    var currentChapterIndex = 0
    
    var isTransitioning = false
    
    // Serial queue for thread-safe player operations
    let playerQueue = DispatchQueue(label: "com.audiobookreader.player", qos: .userInteractive)
    
    override init() {
        super.init()
        // Audio session is configured lazily on first load; observers and remote controls register once here
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        setupRemoteTransportControls()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        for (command, target) in remoteCommandTargets {
            command.removeTarget(target)
        }
        isCleanedUp = true
        cleanup()
        deactivateAudioSession()
    }
    
    // MARK: - Key-Value Observing
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "status", let item = object as? AVPlayerItem {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                switch item.status {
                case .readyToPlay:
                    Log.audio.debug("✅ MultiFileAudioEngine: Player item ready")
                case .failed:
                    let errorDescription = item.error?.localizedDescription ?? "Unknown error"
                    Log.audio.error("❌ MultiFileAudioEngine: Player item failed: \(errorDescription)")
                    
                    // Attempt recovery for failed player items
                    self.recoverFromPlayerFailure(item: item)
                    
                case .unknown:
                    Log.audio.warning("⚠️ MultiFileAudioEngine: Player item status unknown")
                @unknown default:
                    break
                }
            }
        }
    }
    
    private func recoverFromPlayerFailure(item: AVPlayerItem) {
        playerQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Find which player failed
            for (index, playerItem) in self.playerItems {
                if playerItem === item {
                    Log.audio.debug("🔧 MultiFileAudioEngine: Attempting to recover failed chapter \(index + 1)")
                    
                    // Remove the failed player
                    if self.hasAddedObservers.contains(playerItem) {
                        playerItem.removeObserver(self, forKeyPath: "status")
                        self.hasAddedObservers.remove(playerItem)
                    }
                    
                    // Remove from collections
                    self.players.removeValue(forKey: index)
                    self.playerItems.removeValue(forKey: index)
                    
                    // If this was the current player, try to reload it
                    if index == self.currentPlayerIndex {
                        Log.audio.debug("🔄 MultiFileAudioEngine: Reloading current chapter after failure")
                        self.loadChapterPlayer(index)
                        
                        // If we were playing, try to resume
                        if self.isPlaying {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                                self?.play()
                            }
                        }
                    } else {
                        // For non-current players, just mark for lazy reload
                        Log.audio.debug("📝 MultiFileAudioEngine: Non-current chapter \(index + 1) will be reloaded when needed")
                    }
                    
                    break
                }
            }
        }
    }

    // MARK: - Cleanup
    func cleanup() {
        Log.audio.debug("🧹 MultiFileAudioEngine: Starting cleanup...")

        // Remove time observer only from the current player that has it
        if let observer = timeObserver, let currentPlayer = players[currentPlayerIndex] {
            currentPlayer.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        // Remove KVO observers only from items we added them to
        for item in hasAddedObservers {
            item.removeObserver(self, forKeyPath: "status")            
        }
        hasAddedObservers.removeAll()
        
        // Stop ALL players, not just the current one
        for (_, player) in players {
            player.pause()  // Ensure all players are stopped
        }
        players.removeAll()
        playerItems.removeAll()
        chapters.removeAll()
        chapterFiles.removeAll()
        folderURL = nil
        currentPlayerIndex = 0
        
        // Possibly in deinit: never block on main here; skip the observable write off-main
        if Thread.isMainThread {
            isPlaying = false
        }

        Log.audio.debug("✅ MultiFileAudioEngine: Cleanup completed")
    }
    
    private func deactivateAudioSession() {
        if hasSetupAudioSession {
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                hasSetupAudioSession = false
                Log.audio.debug("✅ MultiFileAudioEngine: Audio session deactivated")
            } catch {
                Log.audio.warning("⚠️ MultiFileAudioEngine: Error deactivating audio session: \(error)")
            }
        }
    }
    
    // MARK: - Utility
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

// MARK: - Array Extension
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}