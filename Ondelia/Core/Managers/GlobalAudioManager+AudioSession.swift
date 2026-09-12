import Foundation
import AVFoundation

extension GlobalAudioManager {
    /// Configures the process-wide audio session once.
    ///
    /// There is one session per app, so this belongs to the manager rather than to a per-book
    /// player. Both old engines configured it on every load with different categories, modes
    /// and buffer sizes, so whichever engine loaded last won.
    ///
    /// The session calls run off the main actor: `setActive` is a round trip to the audio
    /// server and iOS flags it as a UI stall when made on the main thread. Awaited from the
    /// load task, which is asynchronous anyway.
    func activateAudioSession() async {
        guard !hasActivatedAudioSession else { return }
        hasActivatedAudioSession = await Task.detached(priority: .userInitiated) {
            Self.activateSession()
        }.value
    }

    nonisolated private static func activateSession() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            // No options: `.allowAirPlay` and `.allowBluetoothA2DP` are only accepted with
            // `.playAndRecord` and make this call fail with paramErr (-50) here, while
            // `.playback` already routes to AirPlay and A2DP anyway.
            //
            // `.default` rather than `.spokenAudio`: the spoken-audio mode switches
            // spatialisation off, which flattens a Dolby Atmos book to plain stereo.
            try session.setCategory(.playback, mode: .default)
            configureSpatialAudio(session)
            try session.setActive(true)
            Log.audio.debug("✅ GlobalAudioManager: Audio session active")
            return true
        } catch {
            Log.audio.error("❌ GlobalAudioManager: Audio session setup failed: \(error)")
            // Minimal fallback: spokenAudio or the routing options can be refused, plain
            // playback is not.
            do {
                try session.setCategory(.playback)
                try session.setActive(true)
                Log.audio.debug("✅ GlobalAudioManager: Fallback audio session active")
                return true
            } catch {
                Log.audio.error("❌ GlobalAudioManager: Fallback audio session failed: \(error)")
                return false
            }
        }
    }

    /// Lets a multichannel (Dolby Digital Plus / Atmos) track reach the output as such instead
    /// of being downmixed to stereo first. Allowed to fail on its own: not worth losing
    /// playback over. Fixed versus head-tracked rendering is the listener's Control Center
    /// setting; iOS gives apps no say in it.
    nonisolated private static func configureSpatialAudio(_ session: AVAudioSession) {
        do {
            try session.setSupportsMultichannelContent(true)
        } catch {
            Log.audio.warning("⚠️ GlobalAudioManager: Multichannel content refused: \(error)")
        }
    }

    /// Subscribes to interruptions and route changes. Registered once, for the app, not once
    /// per engine — the old pair each registered their own and both reacted to every event.
    func observeAudioSession() {
        guard sessionObservers.isEmpty else { return }
        let center = NotificationCenter.default

        sessionObservers.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let info = notification.userInfo
                let type = (info?[AVAudioSessionInterruptionTypeKey] as? UInt)
                    .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
                let shouldResume = (info?[AVAudioSessionInterruptionOptionKey] as? UInt)
                    .map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) }
                    ?? false
                Task { @MainActor in
                    self?.handleInterruption(type: type, shouldResume: shouldResume)
                }
            }
        )

        sessionObservers.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                    .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
                Task { @MainActor in
                    self?.handleRouteChange(reason: reason)
                }
            }
        )
    }

    private func handleInterruption(type: AVAudioSession.InterruptionType?, shouldResume: Bool) {
        switch type {
        case .began:
            Log.audio.debug("🎵 GlobalAudioManager: Interrupted, pausing")
            // Remember whether to come back, so an interruption does not look like the
            // listener pressing pause.
            wasPlayingBeforeInterruption = playbackState == .playing
            pausePlayback()
        case .ended:
            guard shouldResume, wasPlayingBeforeInterruption else { return }
            wasPlayingBeforeInterruption = false
            Log.audio.debug("🎵 GlobalAudioManager: Interruption ended, resuming")
            resumePlayback()
        default:
            break
        }
    }

    private func handleRouteChange(reason: AVAudioSession.RouteChangeReason?) {
        // Headphones pulled out: pause rather than switch to the speaker mid-sentence.
        guard reason == .oldDeviceUnavailable else { return }
        Log.audio.debug("🎧 GlobalAudioManager: Output disconnected, pausing")
        pausePlayback()
    }
}
