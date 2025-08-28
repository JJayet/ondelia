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
        isPlaying = false
    }
    
    // MARK: - Load Audio File
    func loadAudio(url: URL) {
        print("AudioEngine: Loading audio from URL: \(url)")
        print("AudioEngine: File exists: \(FileManager.default.fileExists(atPath: url.path))")
        
        // Setup audio session and remote controls on first load
        setupAudioSession()
        setupRemoteTransportControls()
        
        // Clean up existing player before creating new one
        cleanup()
        
        let asset = AVURLAsset(url: url)
        playerItem = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: playerItem)
        
        // Add time observer with optimized interval for better performance
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }
        
        // Observe duration and status
        playerItem?.addObserver(self, forKeyPath: "duration", options: [.new, .initial], context: nil)
        playerItem?.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
        hasAddedObservers = true
        
        // Setup now playing info asynchronously to avoid blocking
        DispatchQueue.global(qos: .utility).async {
            self.setupNowPlayingInfo(asset: asset)
        }
    }
    
    // MARK: - Playback Controls
    func play() {
        player?.play()
        isPlaying = true
        updateNowPlayingInfo()
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }
    
    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: cmTime)
        updateNowPlayingInfo()
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
        player?.rate = isPlaying ? rate : 0
        updateNowPlayingInfo()
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
        
        // Configure skip intervals
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: 15)]
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: 15)]
    }
}
