import Foundation
import AVFoundation
import MediaPlayer

extension MultiFileAudioEngine {
    // MARK: - Now Playing Info
    func setupNowPlayingInfo(for audiobook: AudiobookModel) {
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
    
    func updateNowPlayingInfo() {
        var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
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

        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: 15)]
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: 15)]
    }
}
