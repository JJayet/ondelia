import Combine
import CoreFoundation
import Foundation

private func playbackCommandCallback(
    _: CFNotificationCenter?,
    observer: UnsafeMutableRawPointer?,
    _: CFNotificationName?,
    _: UnsafeRawPointer?,
    _: CFDictionary?
) {
    guard let observer else { return }
    let coordinator = Unmanaged<PlaybackCommandCoordinator>.fromOpaque(observer).takeUnretainedValue()
    Task { @MainActor in coordinator.consumePendingCommand() }
}

@MainActor
final class PlaybackCommandCoordinator: ObservableObject {
    init() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            playbackCommandCallback,
            NowPlayingSharedStore.commandNotificationName as CFString,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(NowPlayingSharedStore.commandNotificationName as CFString),
            nil
        )
    }

    func consumePendingCommand() {
        guard let command = NowPlayingSharedStore.consumePlaybackCommand() else { return }
        let audioManager = GlobalAudioManager.shared
        switch command {
        case .toggle:
            audioManager.togglePlayback()
        case .skipForward:
            audioManager.skipForward(15)
        case .skipBackward:
            audioManager.skipBackward(15)
        }
    }
}
