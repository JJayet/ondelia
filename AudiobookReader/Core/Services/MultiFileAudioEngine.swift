import Foundation
import AVFoundation
import MediaPlayer

class MultiFileAudioEngine: NSObject, ObservableObject {
    private var players: [AVPlayer] = []
    private var playerItems: [AVPlayerItem] = []
    private var currentPlayerIndex = 0
    private var timeObserver: Any?
    private var chapters: [Chapter] = []
    private var audiobook: Audiobook?
    
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackRate: Float = 1.0
    @Published var currentChapterIndex = 0
    
    private var isTransitioning = false
    
    override init() {
        super.init()
        setupAudioSession()
        setupRemoteTransportControls()
    }
    
    deinit {
        if let observer = timeObserver {
            players.forEach { $0.removeTimeObserver(observer) }
        }
        cleanup()
    }
    
    // MARK: - Audio Session Setup
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.allowAirPlay, .allowBluetoothHFP])
            try audioSession.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }
    
    // MARK: - Load Multi-File Audiobook
    func loadMultiFileAudiobook(_ audiobook: Audiobook) {
        print("🎵 MultiFileAudioEngine: Loading multi-file audiobook: \(audiobook.title ?? "Unknown")")
        
        cleanup()
        
        self.audiobook = audiobook
        
        // Check if this is a folder-based audiobook
        guard let folderPath = audiobook.fileURL,
              FileManager.default.fileExists(atPath: folderPath) else {
            print("❌ MultiFileAudioEngine: Folder path not found: \(audiobook.fileURL ?? "nil")")
            return
        }
        
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folderPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            print("📄 MultiFileAudioEngine: Single file detected, using regular audio engine")
            loadSingleFile(audiobook)
            return
        }
        
        // Load chapters and create players
        loadChaptersFromFolder(folderPath: folderPath, audiobook: audiobook)
    }
    
    private func loadSingleFile(_ audiobook: Audiobook) {
        guard let filePath = audiobook.fileURL else { return }
        let fileURL = URL(fileURLWithPath: filePath)
        
        let asset = AVURLAsset(url: fileURL)
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        
        players = [player]
        playerItems = [playerItem]
        currentPlayerIndex = 0
        duration = audiobook.duration
        
        setupTimeObserver()
        setupNowPlayingInfo(for: audiobook)
        
        // Observe player item status
        playerItem.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
        
        print("✅ MultiFileAudioEngine: Single file loaded successfully")
    }
    
    private func loadChaptersFromFolder(folderPath: String, audiobook: Audiobook) {
        let folderURL = URL(fileURLWithPath: folderPath)
        
        // Get chapters from Core Data, sorted by chapter number
        chapters = (audiobook.chapters?.allObjects as? [Chapter] ?? [])
            .sorted { $0.chapterNumber < $1.chapterNumber }
        
        guard !chapters.isEmpty else {
            print("❌ MultiFileAudioEngine: No chapters found")
            return
        }
        
        // Load manifest file to get file names
        let manifestURL = folderURL.appendingPathComponent("audiobook_manifest.json")
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let chaptersData = manifest["chapters"] as? [[String: Any]] else {
            print("⚠️ MultiFileAudioEngine: No manifest found, trying to load files directly")
            loadChaptersDirectly(folderPath: folderPath, audiobook: audiobook)
            return
        }
        
        // Create players for each chapter file
        var totalDuration: TimeInterval = 0
        
        for (index, chapterData) in chaptersData.enumerated() {
            guard let fileName = chapterData["fileName"] as? String else { continue }
            
            let fileURL = folderURL.appendingPathComponent(fileName)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                print("⚠️ MultiFileAudioEngine: Chapter file not found: \(fileName)")
                continue
            }
            
            let asset = AVURLAsset(url: fileURL)
            let playerItem = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: playerItem)
            
            players.append(player)
            playerItems.append(playerItem)
            
            if let chapterDuration = chapterData["duration"] as? TimeInterval {
                totalDuration += chapterDuration
            }
            
            // Observe player item status
            playerItem.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
            
            print("📖 MultiFileAudioEngine: Loaded chapter \(index + 1): \(fileName)")
        }
        
        duration = totalDuration
        currentPlayerIndex = 0
        
        setupTimeObserver()
        setupNowPlayingInfo(for: audiobook)
        
        // Find the correct chapter index based on current position
        if audiobook.currentPosition > 0 {
            currentChapterIndex = findChapterIndex(for: audiobook.currentPosition)
            currentPlayerIndex = currentChapterIndex
        }
        
        print("✅ MultiFileAudioEngine: Multi-file audiobook loaded successfully")
        print("   Total duration: \(formatTime(totalDuration))")
        print("   Chapters: \(players.count)")
        print("   Starting chapter: \(currentChapterIndex + 1)")
    }
    
    private func loadChaptersDirectly(folderPath: String, audiobook: Audiobook) {
        // Fallback method to load chapters directly from audio files
        let folderURL = URL(fileURLWithPath: folderPath)
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey])
            let audioExtensions = ["mp3", "m4a", "m4b", "aac", "wav", "flac"]
            let audioFiles = contents.filter { url in
                audioExtensions.contains(url.pathExtension.lowercased())
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            
            for (index, fileURL) in audioFiles.enumerated() {
                let asset = AVURLAsset(url: fileURL)
                let playerItem = AVPlayerItem(asset: asset)
                let player = AVPlayer(playerItem: playerItem)
                
                players.append(player)
                playerItems.append(playerItem)
                
                playerItem.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
                
                print("📖 MultiFileAudioEngine: Loaded file \(index + 1): \(fileURL.lastPathComponent)")
            }
            
            currentPlayerIndex = 0
            duration = audiobook.duration
            
            setupTimeObserver()
            setupNowPlayingInfo(for: audiobook)
            
        } catch {
            print("❌ MultiFileAudioEngine: Failed to load chapter files directly: \(error)")
        }
    }
    
    // MARK: - Playback Controls
    func play() {
        guard currentPlayerIndex < players.count else { return }
        
        let currentPlayer = players[currentPlayerIndex]
        currentPlayer.rate = playbackRate
        currentPlayer.play()
        
        isPlaying = true
        updateNowPlayingInfo()
        
        print("▶️ MultiFileAudioEngine: Playing chapter \(currentPlayerIndex + 1)")
    }
    
    func pause() {
        players.forEach { $0.pause() }
        isPlaying = false
        updateNowPlayingInfo()
        
        print("⏸️ MultiFileAudioEngine: Paused")
    }
    
    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func seek(to time: TimeInterval) {
        guard !players.isEmpty else { return }
        
        // Find which chapter this time belongs to
        let targetChapterIndex = findChapterIndex(for: time)
        let targetChapter = chapters[safe: targetChapterIndex]
        
        let chapterStartTime = targetChapter?.startTime ?? 0
        let timeWithinChapter = time - chapterStartTime
        
        // Switch to the correct chapter if needed
        if targetChapterIndex != currentPlayerIndex {
            switchToChapter(targetChapterIndex)
        }
        
        // Seek within the current chapter
        let cmTime = CMTime(seconds: timeWithinChapter, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        players[currentPlayerIndex].seek(to: cmTime)
        
        currentTime = time
        updateNowPlayingInfo()
        
        print("⏭️ MultiFileAudioEngine: Seeked to \(formatTime(time)) (Chapter \(targetChapterIndex + 1))")
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
        if isPlaying {
            players[currentPlayerIndex].rate = rate
        }
        updateNowPlayingInfo()
    }
    
    // MARK: - Chapter Management
    private func switchToChapter(_ chapterIndex: Int) {
        guard chapterIndex >= 0 && chapterIndex < players.count else { return }
        
        // Pause current player
        if currentPlayerIndex < players.count {
            players[currentPlayerIndex].pause()
        }
        
        currentPlayerIndex = chapterIndex
        currentChapterIndex = chapterIndex
        
        print("📖 MultiFileAudioEngine: Switched to chapter \(chapterIndex + 1)")
    }
    
    private func findChapterIndex(for time: TimeInterval) -> Int {
        for (index, chapter) in chapters.enumerated() {
            if time >= chapter.startTime && time < chapter.endTime {
                return index
            }
        }
        
        // If not found, return the last chapter or 0
        return max(0, chapters.count - 1)
    }
    
    // MARK: - Time Observer
    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        
        // Remove existing observer
        if let observer = timeObserver {
            players.forEach { $0.removeTimeObserver(observer) }
        }
        
        // Add observer to current player
        if currentPlayerIndex < players.count {
            timeObserver = players[currentPlayerIndex].addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                self?.updateCurrentTime(time)
            }
        }
    }
    
    private func updateCurrentTime(_ time: CMTime) {
        guard !isTransitioning else { return }
        
        let currentChapterTime = time.seconds
        let chapter = chapters[safe: currentPlayerIndex]
        let chapterStartTime = chapter?.startTime ?? 0
        
        currentTime = chapterStartTime + currentChapterTime
        
        // Check if we need to transition to the next chapter
        if let currentChapter = chapter,
           currentChapterTime >= currentChapter.endTime - currentChapter.startTime - 0.1 { // 0.1 second buffer
            transitionToNextChapter()
        }
    }
    
    private func transitionToNextChapter() {
        guard !isTransitioning,
              currentPlayerIndex < players.count - 1 else { return }
        
        isTransitioning = true
        
        let nextChapterIndex = currentPlayerIndex + 1
        
        print("🔄 MultiFileAudioEngine: Transitioning to chapter \(nextChapterIndex + 1)")
        
        // Pause current player
        players[currentPlayerIndex].pause()
        
        // Switch to next chapter
        switchToChapter(nextChapterIndex)
        
        // Setup time observer for new player
        setupTimeObserver()
        
        // Resume playback if we were playing
        if isPlaying {
            play()
        }
        
        isTransitioning = false
    }
    
    // MARK: - Now Playing Info
    private func setupNowPlayingInfo(for audiobook: Audiobook) {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = audiobook.title ?? "Unknown Title"
        nowPlayingInfo[MPMediaItemPropertyArtist] = audiobook.author ?? "Unknown Author"
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        
        if let coverData = audiobook.coverImageData,
           let coverImage = UIImage(data: coverData) {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: coverImage.size) { _ in coverImage }
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func updateNowPlayingInfo() {
        var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    // MARK: - Remote Control Events
    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        
        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            if let skipEvent = event as? MPSkipIntervalCommandEvent {
                self?.skipForward(skipEvent.interval)
            } else {
                self?.skipForward()
            }
            return .success
        }
        
        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            if let skipEvent = event as? MPSkipIntervalCommandEvent {
                self?.skipBackward(skipEvent.interval)
            } else {
                self?.skipBackward()
            }
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let positionEvent = event as? MPChangePlaybackPositionCommandEvent {
                self?.seek(to: positionEvent.positionTime)
            }
            return .success
        }
        
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: 15)]
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: 15)]
    }
    
    // MARK: - Key-Value Observing
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "status", let item = object as? AVPlayerItem {
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    print("✅ MultiFileAudioEngine: Player item ready")
                case .failed:
                    print("❌ MultiFileAudioEngine: Player item failed: \(item.error?.localizedDescription ?? "Unknown error")")
                case .unknown:
                    print("⚠️ MultiFileAudioEngine: Player item status unknown")
                @unknown default:
                    break
                }
            }
        }
    }
    
    // MARK: - Cleanup
    private func cleanup() {
        if let observer = timeObserver {
            players.forEach { $0.removeTimeObserver(observer) }
            timeObserver = nil
        }
        
        playerItems.forEach { item in
            item.removeObserver(self, forKeyPath: "status")
        }
        
        players.removeAll()
        playerItems.removeAll()
        chapters.removeAll()
    }
    
    // MARK: - Utility
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

// MARK: - Array Extension
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
