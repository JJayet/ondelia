import SwiftUI

@MainActor
@Observable
final class ThemeManager {    
    static let shared = ThemeManager()
    
    var currentTheme: AppTheme = .system
    var accentColor: AccentColor = .blue
    /// Separate, so a listener can step back 10 s to re-hear a sentence and forward 30 s past
    /// a recap. Both keys fall back to the old shared "skipInterval" so existing users keep
    /// the interval they chose.
    var skipBackInterval: SkipInterval = .fifteen
    var skipForwardInterval: SkipInterval = .fifteen
    /// When on, every book plays at `globalSpeed` instead of its own remembered speed.
    var globalSpeedEnabled: Bool = false
    var globalSpeed: Float = 1.0
    /// When on, resuming rewinds a little — more after a long pause. See `+SmartRewind`.
    var smartRewindEnabled: Bool = true
    
    private init() {
        // Load settings without GCD to align with @MainActor
        Task { self.loadSettings() }
    }
    
    private func loadSettings() {
        let theme: AppTheme
        let accent: AccentColor
        // Load from UserDefaults on background queue
        if let themeRawValue = UserDefaults.standard.object(forKey: "selectedTheme") as? Int,
           let loadedTheme = AppTheme(rawValue: themeRawValue) {
            theme = loadedTheme
        } else {
            theme = .system
        }
        
        if let accentRawValue = UserDefaults.standard.object(forKey: "accentColor") as? Int,
           let loadedAccent = AccentColor(rawValue: accentRawValue) {
            accent = loadedAccent
        } else {
            accent = .blue
        }
        
        let storedGlobalSpeed = UserDefaults.standard.object(forKey: "globalSpeed") as? Double
        // `bool(forKey:)` reads an absent key as false, which would ship the feature off.
        let storedSmartRewind = UserDefaults.standard.object(forKey: "smartRewindEnabled") as? Bool

        // Update published properties on main actor
        self.globalSpeedEnabled = UserDefaults.standard.bool(forKey: "globalSpeedEnabled")
        self.globalSpeed = storedGlobalSpeed.map(Float.init) ?? 1.0
        self.smartRewindEnabled = storedSmartRewind ?? true
        self.currentTheme = theme
        self.accentColor = accent
        self.skipBackInterval = Self.loadSkipInterval(key: "skipBackInterval")
        self.skipForwardInterval = Self.loadSkipInterval(key: "skipForwardInterval")

        // Remote commands are registered before this runs, with the default interval.
        GlobalAudioManager.shared.applyRemoteSkipInterval()
    }
    
    func setTheme(_ theme: AppTheme) {
        currentTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: "selectedTheme")
    }
    
    func setAccentColor(_ color: AccentColor) {
        accentColor = color
        UserDefaults.standard.set(color.rawValue, forKey: "accentColor")
    }
    
    private static func loadSkipInterval(key: String) -> SkipInterval {
        let defaults = UserDefaults.standard
        let raw = (defaults.object(forKey: key) ?? defaults.object(forKey: "skipInterval")) as? Int
        return raw.flatMap(SkipInterval.init) ?? .fifteen
    }

    func setSkipBackInterval(_ interval: SkipInterval) {
        skipBackInterval = interval
        UserDefaults.standard.set(interval.rawValue, forKey: "skipBackInterval")
        skipIntervalsDidChange()
    }

    func setSkipForwardInterval(_ interval: SkipInterval) {
        skipForwardInterval = interval
        UserDefaults.standard.set(interval.rawValue, forKey: "skipForwardInterval")
        skipIntervalsDidChange()
    }

    /// The lock screen glyphs and the watch both show the interval, so both follow the setting.
    private func skipIntervalsDidChange() {
        GlobalAudioManager.shared.applyRemoteSkipInterval()
        WatchSyncService.shared.pushSnapshot()
    }

    func setGlobalSpeedEnabled(_ enabled: Bool) {
        globalSpeedEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "globalSpeedEnabled")
    }

    func setGlobalSpeed(_ speed: Float) {
        globalSpeed = speed
        UserDefaults.standard.set(Double(speed), forKey: "globalSpeed")
    }

    func setSmartRewindEnabled(_ enabled: Bool) {
        smartRewindEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "smartRewindEnabled")
    }
}
