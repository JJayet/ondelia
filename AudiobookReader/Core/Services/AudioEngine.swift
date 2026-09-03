//
//  AudioEngine.swift
//  AudiobookReader
//
//  Created by Jonathan Jayet on 14/08/2025.
//


import Foundation
import AVFoundation
import MediaPlayer

@Observable
class AudioEngine: NSObject {
    var player: AVPlayer?
    var playerItem: AVPlayerItem?
    var timeObserver: Any?
    var hasAddedObservers = false
    var hasSetupAudioSession = false
    var isCleanedUp = false
    var remoteCommandTargets: [(MPRemoteCommand, Any)] = []

    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var playbackRate: Float = 1.0
    
    // Thread-safe queue for audio operations
    let audioQueue = DispatchQueue(label: "com.audiobookreader.audioengine", qos: .userInitiated)
    let stateQueue = DispatchQueue(label: "com.audiobookreader.audioengine.state", qos: .utility)
    
    override init() {
        super.init()
        // Audio session is configured lazily in loadAudio(); observers and remote controls register once here
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
        cleanup()
        deactivateAudioSession()
    }
    
    // MARK: - Thread-safe current time updates
    func updateCurrentTime(_ time: TimeInterval) {
        // This is already called on main queue from time observer
        currentTime = time
    }
    
    // MARK: - Key-Value Observing
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "duration", let item = object as? AVPlayerItem {
            Task { [weak self] in
                do {
                    let durationCMTime = try await item.asset.load(.duration)
                    await MainActor.run {
                        self?.duration = durationCMTime.seconds.isFinite ? durationCMTime.seconds : 0
                    }
                } catch {
                    await MainActor.run {
                        self?.duration = 0
                    }
                }
            }
        } else if keyPath == "status", let item = object as? AVPlayerItem {
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    Log.audio.debug("AudioEngine: Player item ready to play")
                case .failed:
                    Log.audio.debug("AudioEngine: Player item failed to load: \(item.error?.localizedDescription ?? "Unknown error")")
                case .unknown:
                    Log.audio.debug("AudioEngine: Player item status unknown")
                @unknown default:
                    Log.audio.debug("AudioEngine: Player item unknown status")
                }
            }
        }
    }
}
