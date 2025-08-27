import SwiftUI
import Combine

class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @Published var currentTheme: AppTheme = .system
    @Published var accentColor: AccentColor = .blue
    @Published var skipInterval: SkipInterval = .fifteen
    
    private init() {
        loadSettings()
    }
    
    private func loadSettings() {
        if let themeRawValue = UserDefaults.standard.object(forKey: "selectedTheme") as? Int,
           let theme = AppTheme(rawValue: themeRawValue) {
            currentTheme = theme
        }
        
        if let accentRawValue = UserDefaults.standard.object(forKey: "accentColor") as? Int,
           let accent = AccentColor(rawValue: accentRawValue) {
            accentColor = accent
        }
        
        if let skipRawValue = UserDefaults.standard.object(forKey: "skipInterval") as? Int,
           let skip = SkipInterval(rawValue: skipRawValue) {
            skipInterval = skip
        }
    }
    
    func updateTheme(_ theme: AppTheme) {
        currentTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: "selectedTheme")
    }
    
    func updateAccentColor(_ color: AccentColor) {
        accentColor = color
        UserDefaults.standard.set(color.rawValue, forKey: "accentColor")
    }
    
    func updateSkipInterval(_ interval: SkipInterval) {
        skipInterval = interval
        UserDefaults.standard.set(interval.rawValue, forKey: "skipInterval")
    }
}

enum AppTheme: Int, CaseIterable {
    case system = 0
    case light = 1
    case dark = 2
    case sepia = 3
    
    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .sepia: return "Sepia"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        case .sepia: return .light
        }
    }
}

enum AccentColor: Int, CaseIterable {
    case blue = 0
    case green = 1
    case orange = 2
    case purple = 3
    case red = 4
    case teal = 5
    
    var displayName: String {
        switch self {
        case .blue: return "Blue"
        case .green: return "Green"
        case .orange: return "Orange"
        case .purple: return "Purple"
        case .red: return "Red"
        case .teal: return "Teal"
        }
    }
    
    var color: Color {
        switch self {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        case .red: return .red
        case .teal: return .teal
        }
    }
}

enum SkipInterval: Int, CaseIterable {
    case fifteen = 15
    case thirty = 30
    case sixty = 60
    
    var displayName: String {
        return "\(rawValue)s"
    }
    
    var seconds: TimeInterval {
        return TimeInterval(rawValue)
    }
}

// MARK: - Theme Environment
struct ThemeEnvironment: EnvironmentKey {
    static let defaultValue = ThemeManager.shared
}

extension EnvironmentValues {
    var theme: ThemeManager {
        get { self[ThemeEnvironment.self] }
        set { self[ThemeEnvironment.self] = newValue }
    }
}

// MARK: - Custom Colors
extension Color {
    static var primaryBackground: Color {
        Color(.systemBackground)
    }
    
    static var secondaryBackground: Color {
        Color(.systemGroupedBackground)
    }
    
    static var cardBackground: Color {
        Color(.secondarySystemGroupedBackground)
    }
    
    static var primaryText: Color {
        Color(.label)
    }
    
    static var secondaryText: Color {
        Color(.secondaryLabel)
    }
}