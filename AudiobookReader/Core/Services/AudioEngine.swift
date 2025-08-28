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
    
    // MARK: - Cleanup
    private func cleanup() {
        audioQueue.sync { [weak self] in
            guard let self = self else { return }
            
            // Remove time observer from current player
            if let observer = self.timeObserver, let currentPlayer = self.player {
                currentPlayer.removeTimeObserver(observer)
                self.timeObserver = nil
            }
            
            // Remove KVO observers if they were added
            if self.hasAddedObservers, let item = self.playerItem {
                item.removeObserver(self, forKeyPath: "duration")
                item.removeObserver(self, forKeyPath: "status")
                self.hasAddedObservers = false
            }
            
            // Clear references
            self.player = nil
            self.playerItem = nil
            
            DispatchQueue.main.async {
                self.isPlaying = false
            }
        }
    }
    
    // MARK: - Load Audio File
    func loadAudio(url: URL) {
        print("AudioEngine: Loading audio from URL: \(url)")
        print("AudioEngine: File exists: \(FileManager.default.fileExists(atPath: url.path))")
        
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Setup audio session and remote controls on first load
            self.setupAudioSession()
            self.setupRemoteTransportControls()
            
            // Clean up existing player before creating new one
            self.cleanup()
            
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
            guard let self = self else { return }
            
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
