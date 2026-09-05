import SwiftUI

@MainActor
@Observable
final class ThemeManager {    
    static let shared = ThemeManager()
    
    var currentTheme: AppTheme = .system
    var accentColor: AccentColor = .blue
    var skipInterval: SkipInterval = .fifteen
    /// When on, every book plays at `globalSpeed` instead of its own remembered speed.
    var globalSpeedEnabled: Bool = false
    var globalSpeed: Float = 1.0
    
    private init() {
        // Load settings without GCD to align with @MainActor
        Task { self.loadSettings() }
    }
    
    private func loadSettings() {
        let theme: AppTheme
        let accent: AccentColor
        let skip: SkipInterval
        
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
        
        if let skipRawValue = UserDefaults.standard.object(forKey: "skipInterval") as? Int,
           let loadedSkip = SkipInterval(rawValue: skipRawValue) {
            skip = loadedSkip
        } else {
            skip = .fifteen
        }
        
        let storedGlobalSpeed = UserDefaults.standard.object(forKey: "globalSpeed") as? Double

        // Update published properties on main actor
        self.globalSpeedEnabled = UserDefaults.standard.bool(forKey: "globalSpeedEnabled")
        self.globalSpeed = storedGlobalSpeed.map(Float.init) ?? 1.0
        self.currentTheme = theme
        self.accentColor = accent
        self.skipInterval = skip

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
    
    func setSkipInterval(_ interval: SkipInterval) {
        skipInterval = interval
        UserDefaults.standard.set(interval.rawValue, forKey: "skipInterval")
        GlobalAudioManager.shared.applyRemoteSkipInterval()
    }

    func setGlobalSpeedEnabled(_ enabled: Bool) {
        globalSpeedEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "globalSpeedEnabled")
    }

    func setGlobalSpeed(_ speed: Float) {
        globalSpeed = speed
        UserDefaults.standard.set(Double(speed), forKey: "globalSpeed")
    }
}
