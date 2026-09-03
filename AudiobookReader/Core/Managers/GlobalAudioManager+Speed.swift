import Foundation

extension GlobalAudioManager {
    /// The speed a book should start at.
    ///
    /// A remembered speed is the whole point of the setting: a narrator you slowed down stays
    /// slow next time. The global override wins when the listener would rather have one speed
    /// everywhere.
    func storedSpeed(for audiobook: AudiobookModel) -> Float {
        let theme = ThemeManager.shared
        let speed = theme.globalSpeedEnabled ? theme.globalSpeed : audiobook.speed
        return speed > 0 ? speed : 1.0
    }

    /// Applies the remembered speed to a freshly loaded engine.
    func applyStoredSpeed(for audiobook: AudiobookModel) {
        let speed = storedSpeed(for: audiobook)
        guard speed != 1.0 else { return }
        player?.setPlaybackRate(speed)
    }

    /// Records a speed change so the next launch, and the next time this book is opened, keep it.
    func rememberSpeed(_ rate: Float) {
        let theme = ThemeManager.shared
        if theme.globalSpeedEnabled {
            theme.setGlobalSpeed(rate)
        }
        guard let audiobook = currentAudiobook,
              AudiobookManager.shared.swiftDataController.isLoaded else { return }
        audiobook.speed = rate
        AudiobookManager.shared.swiftDataController.save()
    }
}
