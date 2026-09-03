import Foundation
import AVFoundation
import MediaPlayer

extension AudioEngine {
    // MARK: - Now Playing Info
    func setupNowPlayingInfo(asset: AVAsset) {
        
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
                Log.audio.debug("Failed to load metadata: \(error)")
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
    
    func updateNowPlayingInfo() {
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
    func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()

        remoteCommandTargets = [
            (commandCenter.playCommand, commandCenter.playCommand.addTarget { [weak self] _ in
                self?.play()
                return .success
            }),
            (commandCenter.pauseCommand, commandCenter.pauseCommand.addTarget { [weak self] _ in
                self?.pause()
                return .success
            }),
            (commandCenter.skipForwardCommand, commandCenter.skipForwardCommand.addTarget { [weak self] event in
                if let skipEvent = event as? MPSkipIntervalCommandEvent {
                    self?.skipForward(skipEvent.interval)
                } else {
                    self?.skipForward()
                }
                return .success
            }),
            (commandCenter.skipBackwardCommand, commandCenter.skipBackwardCommand.addTarget { [weak self] event in
                if let skipEvent = event as? MPSkipIntervalCommandEvent {
                    self?.skipBackward(skipEvent.interval)
                } else {
                    self?.skipBackward()
                }
                return .success
            }),
            (commandCenter.changePlaybackPositionCommand, commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
                if let positionEvent = event as? MPChangePlaybackPositionCommandEvent {
                    self?.seek(to: positionEvent.positionTime)
                }
                return .success
            }),
        ]

        // Configure skip intervals
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: 15)]
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: 15)]
    }
}
