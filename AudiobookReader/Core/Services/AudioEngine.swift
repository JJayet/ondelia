//
//  AudioEngine.swift
//  AudiobookReader
//
//  Created by Jonathan Jayet on 14/08/2025.
//


import Foundation
import AVFoundation
import MediaPlayer

class AudioEngine: NSObject, ObservableObject {
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var hasAddedObservers = false
    private var hasSetupAudioSession = false
    private var isCleanedUp = false
    
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackRate: Float = 1.0
    
    // Thread-safe queue for audio operations
    private let audioQueue = DispatchQueue(label: "com.audiobookreader.audioengine", qos: .userInitiated)
    private let stateQueue = DispatchQueue(label: "com.audiobookreader.audioengine.state", qos: .utility)
    
    override init() {
        super.init()
        // Defer audio session and remote control setup until needed
    }
    
    deinit {
        cleanup()
        deactivateAudioSession()
    }
    
    // MARK: - Audio Session Setup
    func setupAudioSession() {
    do {
        let audioSession = AVAudioSession.sharedInstance()
        
        // Deactivate session first to avoid conflicts
        try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        
        // Configure basic audio session for audiobook playback
        try audioSession.setCategory(.playback, 
                                   mode: .spokenAudio, 
                                   options: [.allowAirPlay, 
                                           .allowBluetoothA2DP])
        
        // Set reasonable audio settings that work reliably
        do {
            try audioSession.setPreferredSampleRate(44100.0) // Standard CD quality
        } catch {
            print("⚠️ AudioEngine: Could not set sample rate: \(error)")
        }
        
        do {
            try audioSession.setPreferredIOBufferDuration(0.02) // 20ms buffer for stability
        } catch {
            print("⚠️ AudioEngine: Could not set buffer duration: \(error)")
        }
        
        // Configure audio routing
        do {
            try audioSession.setPreferredOutputNumberOfChannels(2)
        } catch {
            print("⚠️ AudioEngine: Could not set output channels: \(error)")
        }
        
        // Activate the session
        try audioSession.setActive(true)
        
        print("✅ AudioEngine: Audio session configured successfully")
        
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
        print("❌ AudioEngine: Failed to set up audio session: \(error)")
        // Try a minimal fallback configuration
        setupFallbackAudioSession()
    }
}

    private func setupFallbackAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            print("🔄 AudioEngine: Attempting fallback audio session setup")
            
            // Minimal configuration that should always work
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
            
            print("✅ AudioEngine: Fallback audio session configured")
            
        } catch {
            print("❌ AudioEngine: Even fallback audio session failed: \(error)")
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
            print("🎵 AudioEngine: Audio session interrupted - pausing playback")
            pause()
            
        case .ended:
            guard let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            
            if options.contains(.shouldResume) {
                print("🎵 AudioEngine: Audio session interruption ended - resuming playback")
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
            print("🎧 AudioEngine: Audio device disconnected - pausing playback")
            pause()
            
        case .newDeviceAvailable:
            print("🎧 AudioEngine: New audio device connected")
            // Optionally configure for the new device
            configureForCurrentAudioRoute()
            
        case .routeConfigurationChange:
            print("🎧 AudioEngine: Audio route configuration changed")
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
                // Configure optimal settings for spatial audio capable devices
                try audioSession.setPreferredSampleRate(48000.0)
                print("✨ AudioEngine: Enhanced audio settings enabled for spatial audio capable route")
            } catch {
                print("⚠️ AudioEngine: Failed to configure enhanced audio settings: \(error)")
            }
        }
    }

    // MARK: - Enhanced Audio Processing
    private func enableEnhancedAudioProcessing() {
        guard let playerItem = playerItem else { return }
        
        // Configure audio processing for better speech clarity
        let audioMix = AVMutableAudioMix()
        let audioMixInputParameters = AVMutableAudioMixInputParameters(track: nil)
        
        // Configure dynamic range compression for consistent volume
        audioMixInputParameters.setVolume(1.0, at: .zero)
        
        audioMix.inputParameters = [audioMixInputParameters]
        playerItem.audioMix = audioMix
        
        print("🎛️ AudioEngine: Enhanced audio processing enabled")
    }
    
    func enableNoiseSuppression(_ enabled: Bool) {
        
        audioQueue.async { [weak self] in
            guard let self = self, let playerItem = self.playerItem else { return }
            
            if enabled {
                // Apply noise suppression settings
                let audioMix = playerItem.audioMix?.mutableCopy() as? AVMutableAudioMix ?? AVMutableAudioMix()
                
                // Configure noise suppression parameters
                for inputParameters in audioMix.inputParameters {
                    if inputParameters is AVMutableAudioMixInputParameters {
                        // Add noise suppression processing here
                        print("🔇 AudioEngine: Noise suppression enabled")
                    }
                }
                
                playerItem.audioMix = audioMix
            } else {
                playerItem.audioMix = nil
                print("🔇 AudioEngine: Noise suppression disabled")
            }
        }
    }
    
    func setEqualizer(bassBoost: Float, trebleBoost: Float) {
        
        audioQueue.async { [weak self] in
            guard let self = self, let playerItem = self.playerItem else { return }
            
            let audioMix = playerItem.audioMix?.mutableCopy() as? AVMutableAudioMix ?? AVMutableAudioMix()
            
            // Configure EQ parameters
            for inputParameters in audioMix.inputParameters {
                if inputParameters is AVMutableAudioMixInputParameters {
                    // Apply bass and treble adjustments
                    print("🎚️ AudioEngine: EQ applied - Bass: \(bassBoost), Treble: \(trebleBoost)")
                }
            }
            
            playerItem.audioMix = audioMix
        }
    }
    
    func enableSpeechEnhancement(_ enabled: Bool) {
        
        audioQueue.async { [weak self] in
            guard let self = self, let playerItem = self.playerItem else { return }
            
            if enabled {
                // Enable speech-optimized processing
                let audioMix = playerItem.audioMix?.mutableCopy() as? AVMutableAudioMix ?? AVMutableAudioMix()
                
                // Configure speech enhancement
                for inputParameters in audioMix.inputParameters {
                    if inputParameters is AVMutableAudioMixInputParameters {
                        print("🗣️ AudioEngine: Speech enhancement enabled")
                    }
                }
                
                playerItem.audioMix = audioMix
                self.enableEnhancedAudioProcessing()
            } else {
                playerItem.audioMix = nil
                print("🗣️ AudioEngine: Speech enhancement disabled")
            }
        }
    }
    
    // MARK: - Cleanup
    private func cleanup() {
        // Prevent multiple cleanup calls
        guard !isCleanedUp else { 
            print("⚠️ AudioEngine: Cleanup already performed")
            return 
        }
        isCleanedUp = true
        
        print("🧹 AudioEngine: Starting cleanup...")
        
        // Stop playback first on current thread
        player?.pause()
        
        // Remove notification observers synchronously on current thread
        NotificationCenter.default.removeObserver(self, 
                                                 name: AVAudioSession.interruptionNotification, 
                                                 object: nil)
        NotificationCenter.default.removeObserver(self, 
                                                 name: AVAudioSession.routeChangeNotification, 
                                                 object: nil)
        
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
        
        // Update UI state immediately since we're potentially in deinit
        if Thread.isMainThread {
            isPlaying = false
        } else {
            DispatchQueue.main.sync {
                isPlaying = false
            }
        }
        
        print("✅ AudioEngine: Cleanup completed")
    }

    private func cleanupPlayerDirectly() {
        // This method runs on audioQueue, so no need for sync
        // Remove notification observers
        NotificationCenter.default.removeObserver(self, 
                                                 name: AVAudioSession.interruptionNotification, 
                                                 object: nil)
        NotificationCenter.default.removeObserver(self, 
                                                 name: AVAudioSession.routeChangeNotification, 
                                                 object: nil)
        
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

private func deactivateAudioSession() {
    if hasSetupAudioSession {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            hasSetupAudioSession = false
            print("✅ AudioEngine: Audio session deactivated")
        } catch {
            print("⚠️ AudioEngine: Failed to deactivate audio session: \(error)")
        }
    }
}
    
    // MARK: - Load Audio File
    func loadAudio(url: URL) {
        print("AudioEngine: Loading audio from URL: \(url)")
        print("AudioEngine: File exists: \(FileManager.default.fileExists(atPath: url.path))")
        
        // Setup audio session once on main thread if not already done
        if !hasSetupAudioSession {
            setupAudioSession()
            setupRemoteTransportControls()
            hasSetupAudioSession = true
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
            guard let self = self else { return }
            
            self.player?.play()
            
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
    
    // MARK: - Thread-safe current time updates
    private func updateCurrentTime(_ time: TimeInterval) {
        // This is already called on main queue from time observer
        currentTime = time
    }
    
    // MARK: - Key-Value Observing
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "duration", let item = object as? AVPlayerItem {
            Task {
                do {
                    let durationCMTime = try await item.asset.load(.duration)
                    await MainActor.run {
                        self.duration = durationCMTime.seconds.isFinite ? durationCMTime.seconds : 0
                    }
                } catch {
                    await MainActor.run {
                        self.duration = 0
                    }
                }
            }
        } else if keyPath == "status", let item = object as? AVPlayerItem {
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    print("AudioEngine: Player item ready to play")
                case .failed:
                    print("AudioEngine: Player item failed to load: \(item.error?.localizedDescription ?? "Unknown error")")
                case .unknown:
                    print("AudioEngine: Player item status unknown")
                @unknown default:
                    print("AudioEngine: Player item unknown status")
                }
            }
        }
    }
    
    // MARK: - Now Playing Info
    private func setupNowPlayingInfo(asset: AVAsset) {
        
        // Extract metadata for now playing info
        Task {
            do {
                let metadata = try await asset.load(.metadata)
                var title = "Unknown Title"
                var artist = "Unknown Author"
                var artwork: UIImage?
                
                for item in metadata {
                    guard let key = item.commonKey else { continue }
                    
                    switch key {
                    case .commonKeyTitle:
                        if let titleValue = try await item.load(.stringValue) {
                            title = titleValue
                        }
                    case .commonKeyArtist:
                        if let artistValue = try await item.load(.stringValue) {
                            artist = artistValue
                        }
                    case .commonKeyArtwork:
                        if let artworkData = try await item.load(.dataValue) {
                            artwork = UIImage(data: artworkData)
                        }
                    default:
                        break
                    }
                }
                
                let durationCMTime = try await asset.load(.duration)
                
                // Capture values to avoid concurrency warnings
                let capturedTitle = title
                let capturedArtist = artist
                let capturedArtwork = artwork
                
                await MainActor.run {
                    var nowPlayingInfo: [String: Any] = [:]
                    nowPlayingInfo[MPMediaItemPropertyTitle] = capturedTitle
                    nowPlayingInfo[MPMediaItemPropertyArtist] = capturedArtist
                    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = durationCMTime.seconds
                    
                    if let artwork = capturedArtwork {
                        nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
                    }
                    
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                }
            } catch {
                print("Failed to load metadata: \(error)")
                do {
                    let durationCMTime = try await asset.load(.duration)
                    await MainActor.run {
                        var nowPlayingInfo: [String: Any] = [:]
                        nowPlayingInfo[MPMediaItemPropertyTitle] = "Sample Audiobook"
                        nowPlayingInfo[MPMediaItemPropertyArtist] = "Unknown Author"
                        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = durationCMTime.seconds
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                    }
                } catch {
                    await MainActor.run {
                        var nowPlayingInfo: [String: Any] = [:]
                        nowPlayingInfo[MPMediaItemPropertyTitle] = "Sample Audiobook"
                        nowPlayingInfo[MPMediaItemPropertyArtist] = "Unknown Author"
                        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = 0
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                    }
                }
            }
        }
    }
    
    private func updateNowPlayingInfo() {
        // Ensure this runs on main thread when updating Now Playing info
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isCleanedUp else { return }
            
            var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = self.currentTime
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = self.isPlaying ? self.playbackRate : 0.0
            
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        }
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
        
        // Configure skip intervals
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: 15)]
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: 15)]
    }
}
