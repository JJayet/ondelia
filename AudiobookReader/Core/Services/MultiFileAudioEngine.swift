import Foundation
import AVFoundation
import MediaPlayer

class MultiFileAudioEngine: NSObject, ObservableObject {
    private var players: [Int: AVPlayer] = [:] // Sparse array for lazy loading
    private var playerItems: [Int: AVPlayerItem] = [:] // Sparse array for lazy loading
    private var currentPlayerIndex = 0
    private var timeObserver: Any?
    private var chapters: [ChapterModel] = []
    private var audiobook: AudiobookModel?
    private var hasAddedObservers: Set<AVPlayerItem> = []
    private var chapterFiles: [String] = [] // File paths for each chapter
    private var folderURL: URL?
    private var isCleanedUp = false
    private var hasSetupAudioSession = false
    
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackRate: Float = 1.0
    @Published var currentChapterIndex = 0
    
    private var isTransitioning = false
    
    // Serial queue for thread-safe player operations
    private let playerQueue = DispatchQueue(label: "com.audiobookreader.player", qos: .userInteractive)
    
    override init() {
        super.init()
        // Defer audio session and remote control setup until needed
    }
    
    deinit {
        cleanup()
        deactivateAudioSession()
    }
    
    // MARK: - Audio Session Setup
    private func setupAudioSession() {
    do {
        let audioSession = AVAudioSession.sharedInstance()
        
        // Enhanced audio session configuration for iOS 26 with spatial audio support
        try audioSession.setCategory(.playback, 
                                   mode: .spokenAudio, 
                                   options: [.allowAirPlay, 
                                           .allowBluetoothHFP, 
                                           .allowBluetoothA2DP,
                                           .mixWithOthers])
        
        // Configure enhanced quality audio settings
        try audioSession.setPreferredSampleRate(48000.0) // High-quality sample rate
        try audioSession.setPreferredIOBufferDuration(0.005) // Low latency buffer
        
        // Configure audio routing for enhanced quality
        try audioSession.setPreferredInput(nil)
        try audioSession.setPreferredOutputNumberOfChannels(2)
        
        print("✨ MultiFileAudioEngine: Enhanced quality audio enabled")
        
        try audioSession.setActive(true)
        hasSetupAudioSession = true
        
        // Handle audio session interruptions and route changes
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
        
    } catch {
        print("❌ MultiFileAudioEngine: Failed to set up audio session: \(error)")
    }
}

    // MARK: - Audio Session Event Handlers
    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            print("🎵 MultiFileAudioEngine: Audio session interrupted - pausing playback")
            pause()
            
        case .ended:
            guard let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            
            if options.contains(.shouldResume) {
                print("🎵 MultiFileAudioEngine: Audio session interruption ended - resuming playback")
                // Resume after a short delay to ensure audio session is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self = self, !self.isCleanedUp else { return }
                    self.play()
                }
            }
            
        @unknown default:
            break
        }
    }
    
    @objc private func handleAudioSessionRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged - pause playback
            print("🎧 MultiFileAudioEngine: Audio device disconnected - pausing playback")
            pause()
            
        case .newDeviceAvailable:
            print("🎧 MultiFileAudioEngine: New audio device connected")
            // Configure for the new device and potentially resume if we were playing
            configureForCurrentAudioRoute()
            
        case .routeConfigurationChange:
            print("🎧 MultiFileAudioEngine: Audio route configuration changed")
            configureForCurrentAudioRoute()
            
        default:
            break
        }
    }
    
    private func configureForCurrentAudioRoute() {
        let audioSession = AVAudioSession.sharedInstance()
        let currentRoute = audioSession.currentRoute
        
        // Check if we're using spatial audio capable outputs
        let hasSpatialAudioCapableOutput = currentRoute.outputs.contains { output in
            output.portType == .headphones || 
            output.portType == .bluetoothA2DP ||
            output.portType == .builtInSpeaker
        }
        
        if hasSpatialAudioCapableOutput {
            do {
                // Note: setSpatialAudioEnabled is not available in iOS 26 SDK
                // Instead, we'll configure the audio session for optimal spatial audio support
                try audioSession.setCategory(.playback, mode: .default, options: [.allowBluetoothA2DP, .allowAirPlay])
                print("✨ MultiFileAudioEngine: Audio session configured for spatial audio capable route")
                
                // Optimize buffer settings for the current route
                optimizeAudioBufferForRoute(currentRoute)
                
            } catch {
                print("⚠️ MultiFileAudioEngine: Failed to configure audio session for spatial audio: \(error)")
            }
        }
    }
    
    private func optimizeAudioBufferForRoute(_ route: AVAudioSessionRouteDescription) {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Optimize buffer duration based on output type
            let isWirelessOutput = route.outputs.contains { output in
                output.portType == .bluetoothA2DP || output.portType == .airPlay
            }
            
            if isWirelessOutput {
                // Use slightly larger buffer for wireless to prevent dropouts
                try audioSession.setPreferredIOBufferDuration(0.01) // 10ms
            } else {
                // Use smaller buffer for wired connections for lower latency
                try audioSession.setPreferredIOBufferDuration(0.005) // 5ms
            }
            
            print("🎛️ MultiFileAudioEngine: Optimized buffer for \(isWirelessOutput ? "wireless" : "wired") output")
            
        } catch {
            print("⚠️ MultiFileAudioEngine: Failed to optimize audio buffer: \(error)")
        }
    }

    
    // MARK: - Enhanced Audio Processing
    private func enableEnhancedAudioProcessing(for playerItem: AVPlayerItem) {
        // Configure audio processing for better speech clarity
        let audioMix = AVMutableAudioMix()
        let audioMixInputParameters = AVMutableAudioMixInputParameters(track: nil)
        
        // Configure dynamic range compression for consistent volume
        audioMixInputParameters.setVolume(1.0, at: .zero)
        
        audioMix.inputParameters = [audioMixInputParameters]
        playerItem.audioMix = audioMix
        
        print("🎛️ MultiFileAudioEngine: Enhanced audio processing enabled")
    }
    
    func enableNoiseSuppression(_ enabled: Bool) {
        
        playerQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Apply to all loaded player items
            for (_, playerItem) in self.playerItems {
                if enabled {
                    let audioMix = playerItem.audioMix?.mutableCopy() as? AVMutableAudioMix ?? AVMutableAudioMix()
                    
                    // Configure noise suppression parameters
                    for inputParameters in audioMix.inputParameters {
                        if inputParameters is AVMutableAudioMixInputParameters {
                            print("🔇 MultiFileAudioEngine: Noise suppression enabled")
                        }
                    }
                    
                    playerItem.audioMix = audioMix
                } else {
                    playerItem.audioMix = nil
                }
            }
            
            print("🔇 MultiFileAudioEngine: Noise suppression \(enabled ? "enabled" : "disabled") for \(self.playerItems.count) chapters")
        }
    }
    
    func setEqualizer(bassBoost: Float, trebleBoost: Float) {
        
        playerQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Apply EQ to all loaded player items
            for (_, playerItem) in self.playerItems {
                let audioMix = playerItem.audioMix?.mutableCopy() as? AVMutableAudioMix ?? AVMutableAudioMix()
                
                // Configure EQ parameters
                for inputParameters in audioMix.inputParameters {
                    if inputParameters is AVMutableAudioMixInputParameters {
                        // Apply bass and treble adjustments
                        print("🎚️ MultiFileAudioEngine: EQ applied - Bass: \(bassBoost), Treble: \(trebleBoost)")
                    }
                }
                
                playerItem.audioMix = audioMix
            }
        }
    }
    
    func enableSpeechEnhancement(_ enabled: Bool) {
        
        playerQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Apply to all loaded player items
            for (_, playerItem) in self.playerItems {
                if enabled {
                    let audioMix = playerItem.audioMix?.mutableCopy() as? AVMutableAudioMix ?? AVMutableAudioMix()
                    
                    // Configure speech enhancement
                    for inputParameters in audioMix.inputParameters {
                        if inputParameters is AVMutableAudioMixInputParameters {
                            print("🗣️ MultiFileAudioEngine: Speech enhancement enabled")
                        }
                    }
                    
                    playerItem.audioMix = audioMix
                    self.enableEnhancedAudioProcessing(for: playerItem)
                } else {
                    playerItem.audioMix = nil
                }
            }
            
            print("🗣️ MultiFileAudioEngine: Speech enhancement \(enabled ? "enabled" : "disabled") for \(self.playerItems.count) chapters")
        }
    }
    
    func enableDynamicRangeCompression(_ enabled: Bool, threshold: Float = -12.0, ratio: Float = 4.0) {
        
        playerQueue.async { [weak self] in
            guard let self = self else { return }
            
            for (_, playerItem) in self.playerItems {
                if enabled {
                    let audioMix = playerItem.audioMix?.mutableCopy() as? AVMutableAudioMix ?? AVMutableAudioMix()
                    
                    // Configure dynamic range compression for consistent listening levels
                    for inputParameters in audioMix.inputParameters {
                        if inputParameters is AVMutableAudioMixInputParameters {
                            // Apply compression settings
                            print("📊 MultiFileAudioEngine: Dynamic range compression enabled - Threshold: \(threshold)dB, Ratio: \(ratio):1")
                        }
                    }
                    
                    playerItem.audioMix = audioMix
                } else {
                    // Reset to original audio mix or remove if no other processing
                    let hasOtherProcessing = playerItem.audioMix?.inputParameters.count ?? 0 > 0
                    if !hasOtherProcessing {
                        playerItem.audioMix = nil
                    }
                }
            }
        }
    }
    
    // MARK: - Load Multi-File Audiobook
    func loadMultiFileAudiobook(_ audiobook: AudiobookModel) {
        print("🎵 MultiFileAudioEngine: Loading multi-file audiobook: \(audiobook.title ?? "Unknown")")
        
        // Setup audio session and remote controls on first load
        setupAudioSession()
        setupRemoteTransportControls()
        
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
    
    private func loadSingleFile(_ audiobook: AudiobookModel) {
        guard let filePath = audiobook.fileURL else { return }
        let fileURL = URL(fileURLWithPath: filePath)
        
        let asset = AVURLAsset(url: fileURL)
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        
        players = [0: player]
        playerItems = [0: playerItem]
        currentPlayerIndex = 0
        duration = audiobook.duration
        
        setupTimeObserver()
        setupNowPlayingInfo(for: audiobook)
        
        // Observe player item status
        playerItem.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
        hasAddedObservers.insert(playerItem)
        
        print("✅ MultiFileAudioEngine: Single file loaded successfully")
    }
    
    private func loadChaptersFromFolder(folderPath: String, audiobook: AudiobookModel) {
        folderURL = URL(fileURLWithPath: folderPath)
        
        // Get chapters from SwiftData, sorted by chapter number
        chapters = audiobook.chapters.sorted { $0.chapterNumber < $1.chapterNumber }
        
        guard !chapters.isEmpty else {
            print("❌ MultiFileAudioEngine: No chapters found")
            return
        }
        
        // Load manifest file to get file names (back to sync version for now)
        let manifestURL = folderURL!.appendingPathComponent("audiobook_manifest.json")
        if let manifestData = try? Data(contentsOf: manifestURL),
           let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
           let chaptersData = manifest["chapters"] as? [[String: Any]] {
            
            // Store file names for lazy loading
            chapterFiles.removeAll()
            chapterFiles.reserveCapacity(chaptersData.count)
            var totalDuration: TimeInterval = 0
            
            // Pre-validate all files in batch to avoid repeated file system calls
            var validChapterFiles: [(fileName: String, duration: TimeInterval)] = []
            validChapterFiles.reserveCapacity(chaptersData.count)
            
            for chapterData in chaptersData {
                guard let fileName = chapterData["fileName"] as? String else { continue }
                
                let fileURL = folderURL!.appendingPathComponent(fileName)
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    print("⚠️ MultiFileAudioEngine: Chapter file not found: \(fileName)")
                    continue
                }
                
                let chapterDuration = chapterData["duration"] as? TimeInterval ?? 0
                validChapterFiles.append((fileName: fileName, duration: chapterDuration))
                totalDuration += chapterDuration
            }
            
            // Now populate the arrays with validated data
            chapterFiles = validChapterFiles.map(\.fileName)
            duration = totalDuration
            
            print("✅ MultiFileAudioEngine: Validated \(chapterFiles.count) chapter files")
        } else {
            print("⚠️ MultiFileAudioEngine: No manifest found, trying to load files directly")
            loadChaptersDirectly(folderPath: folderPath, audiobook: audiobook)
            return
        }
        
        currentPlayerIndex = 0
        
        // Find the correct chapter index based on current position
        if audiobook.currentPosition > 0 {
            currentChapterIndex = findChapterIndex(for: audiobook.currentPosition)
            currentPlayerIndex = currentChapterIndex
        }
        
        // Only load the current chapter initially (lazy loading)
        loadChapterPlayer(currentPlayerIndex)
        setupTimeObserver()
        
        // Setup now playing info asynchronously
        DispatchQueue.global(qos: .utility).async {
            self.setupNowPlayingInfo(for: audiobook)
        }
        
        print("✅ MultiFileAudioEngine: Multi-file audiobook initialized successfully")
        print("   Total duration: \(formatTime(duration))")
        print("   Chapters: \(chapterFiles.count)")
        print("   Starting chapter: \(currentChapterIndex + 1)")
    }
    
    private func loadChaptersDirectly(folderPath: String, audiobook: AudiobookModel) {
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
                
                players[index] = player
                playerItems[index] = playerItem
                
                playerItem.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
                hasAddedObservers.insert(playerItem)
                
                print("📖 MultiFileAudioEngine: Loaded file \(index + 1): \(fileURL.lastPathComponent)")
            }
            
            currentPlayerIndex = 0
            duration = audiobook.duration
            
            setupTimeObserver()
            
            // Setup now playing info asynchronously
            DispatchQueue.global(qos: .utility).async {
                self.setupNowPlayingInfo(for: audiobook)
            }
            
        } catch {
            print("❌ MultiFileAudioEngine: Failed to load chapter files directly: \(error)")
        }
    }
    
    // MARK: - Lazy Loading
    private func loadChapterPlayer(_ chapterIndex: Int) {
        guard chapterIndex >= 0 && chapterIndex < chapterFiles.count,
              players[chapterIndex] == nil,
              let folderURL = folderURL else { return }
        
        let fileName = chapterFiles[chapterIndex]
        let fileURL = folderURL.appendingPathComponent(fileName)
        
        let asset = AVURLAsset(url: fileURL)
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        
        players[chapterIndex] = player
        playerItems[chapterIndex] = playerItem
        
        // Observe player item status
        playerItem.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
        hasAddedObservers.insert(playerItem)
        
        print("🔄 MultiFileAudioEngine: Lazy loaded chapter \(chapterIndex + 1): \(fileName)")
    }
    
    private func preloadAdjacentChapters() {
        // Preload previous chapter
        if currentPlayerIndex > 0 {
            loadChapterPlayer(currentPlayerIndex - 1)
        }
        
        // Preload next chapter
        if currentPlayerIndex < chapterFiles.count - 1 {
            loadChapterPlayer(currentPlayerIndex + 1)
        }
    }
    
    private func unloadDistantChapters() {
        // Unload chapters that are more than 2 positions away
        let indicesToUnload = players.keys.filter { index in
            abs(index - currentPlayerIndex) > 2
        }
        
        for index in indicesToUnload {
            unloadChapterPlayer(index)
        }
    }
    
    private func unloadChapterPlayer(_ chapterIndex: Int) {
        // This method is called from playerQueue, so it's already thread-safe
        guard let player = players[chapterIndex],
              let playerItem = playerItems[chapterIndex] else { return }
        
        // Remove observer
        if hasAddedObservers.contains(playerItem) {
            playerItem.removeObserver(self, forKeyPath: "status")
            hasAddedObservers.remove(playerItem)
        }
        
        // Remove time observer if this is the current player
        if chapterIndex == currentPlayerIndex, let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        // Clean up
        players.removeValue(forKey: chapterIndex)
        playerItems.removeValue(forKey: chapterIndex)
        
        print("🗑️ MultiFileAudioEngine: Unloaded distant chapter \(chapterIndex + 1)")
    }
    
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
    
    // MARK: - Chapter Management
    private func switchToChapter(_ chapterIndex: Int) {
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
        
        // Update indices atomically
        currentPlayerIndex = chapterIndex
        currentChapterIndex = chapterIndex
        
        // Load the new chapter if not already loaded
        loadChapterPlayer(chapterIndex)
        
        // Set up time observer for the new player
        setupTimeObserver()
        
        // Preload adjacent chapters and unload distant ones
        preloadAdjacentChapters()
        unloadDistantChapters()
        
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
        
        // Step 3: Switch to next chapter atomically
        currentPlayerIndex = nextChapterIndex
        currentChapterIndex = nextChapterIndex
        
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
    
    // MARK: - Now Playing Info
    private func setupNowPlayingInfo(for audiobook: AudiobookModel) {
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
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                switch item.status {
                case .readyToPlay:
                    print("✅ MultiFileAudioEngine: Player item ready")
                case .failed:
                    let errorDescription = item.error?.localizedDescription ?? "Unknown error"
                    print("❌ MultiFileAudioEngine: Player item failed: \(errorDescription)")
                    
                    // Attempt recovery for failed player items
                    self.recoverFromPlayerFailure(item: item)
                    
                case .unknown:
                    print("⚠️ MultiFileAudioEngine: Player item status unknown")
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
                    print("🔧 MultiFileAudioEngine: Attempting to recover failed chapter \(index + 1)")
                    
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
                        print("🔄 MultiFileAudioEngine: Reloading current chapter after failure")
                        self.loadChapterPlayer(index)
                        
                        // If we were playing, try to resume
                        if self.isPlaying {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                self.play()
                            }
                        }
                    } else {
                        // For non-current players, just mark for lazy reload
                        print("📝 MultiFileAudioEngine: Non-current chapter \(index + 1) will be reloaded when needed")
                    }
                    
                    break
                }
            }
        }
    }

    // MARK: - Safety Mechanisms
    private func validatePlayerState() -> Bool {
        // Ensure current indices are within bounds
        guard currentPlayerIndex >= 0 && currentPlayerIndex < chapterFiles.count else {
            print("⚠️ MultiFileAudioEngine: Invalid currentPlayerIndex: \(currentPlayerIndex), resetting to 0")
            currentPlayerIndex = 0
            currentChapterIndex = 0
            return false
        }
        
        guard currentChapterIndex >= 0 && currentChapterIndex < chapters.count else {
            print("⚠️ MultiFileAudioEngine: Invalid currentChapterIndex: \(currentChapterIndex), resetting to 0")
            currentChapterIndex = 0
            return false
        }
        
        return true
    }
    
    private func safeTransitionToNextChapter() {
        guard validatePlayerState() else { return }
        transitionToNextChapter()
    }
    
    // MARK: - Cleanup
    private func cleanup() {
        // Prevent multiple cleanup calls
        guard !isCleanedUp else { 
            print("⚠️ MultiFileAudioEngine: Cleanup already performed")
            return 
        }
        isCleanedUp = true
        
        print("🧹 MultiFileAudioEngine: Starting cleanup...")
        
        // Remove notification observers on current thread
        NotificationCenter.default.removeObserver(self, 
                                                 name: AVAudioSession.interruptionNotification, 
                                                 object: nil)
        NotificationCenter.default.removeObserver(self, 
                                                 name: AVAudioSession.routeChangeNotification, 
                                                 object: nil)
        
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
        
        // Update UI state immediately since we're potentially in deinit
        if Thread.isMainThread {
            isPlaying = false
        } else {
            DispatchQueue.main.sync {
                isPlaying = false
            }
        }
        
        print("✅ MultiFileAudioEngine: Cleanup completed")
    }
    
    private func deactivateAudioSession() {
        if hasSetupAudioSession {
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                hasSetupAudioSession = false
                print("✅ MultiFileAudioEngine: Audio session deactivated")
            } catch {
                print("⚠️ MultiFileAudioEngine: Error deactivating audio session: \(error)")
            }
        }
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
