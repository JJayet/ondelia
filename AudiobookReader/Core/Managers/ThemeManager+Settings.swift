import SwiftUI

enum AppTheme: Int, CaseIterable {
    case system = 0
    case light = 1
    case dark = 2
    
    var displayName: String {
        switch self {
        case .system: return NSLocalizedString("System", comment: "System appearance theme")
        case .light: return NSLocalizedString("Light", comment: "Light appearance theme")
        case .dark: return NSLocalizedString("Dark", comment: "Dark appearance theme")
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
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
        case .blue: return NSLocalizedString("Blue", comment: "Blue accent color")
        case .green: return NSLocalizedString("Green", comment: "Green accent color")
        case .orange: return NSLocalizedString("Orange", comment: "Orange accent color")
        case .purple: return NSLocalizedString("Purple", comment: "Purple accent color")
        case .red: return NSLocalizedString("Red", comment: "Red accent color")
        case .teal: return NSLocalizedString("Teal", comment: "Teal accent color")
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

enum TranscriptionLanguage: String, CaseIterable {
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portuguese = "pt"
    case japanese = "ja"
    case korean = "ko"
    case chinese = "zh"
    
    var displayName: String {
        switch self {
        case .english: return NSLocalizedString("English", comment: "English language")
        case .spanish: return NSLocalizedString("Spanish", comment: "Spanish language")
        case .french: return NSLocalizedString("French", comment: "French language")
        case .german: return NSLocalizedString("German", comment: "German language")
        case .italian: return NSLocalizedString("Italian", comment: "Italian language")
        case .portuguese: return NSLocalizedString("Portuguese", comment: "Portuguese language")
        case .japanese: return NSLocalizedString("Japanese", comment: "Japanese language")
        case .korean: return NSLocalizedString("Korean", comment: "Korean language")
        case .chinese: return NSLocalizedString("Chinese", comment: "Chinese language")
        }
    }
    
    var locale: Locale {
        return Locale(identifier: rawValue)
    }
}

/// The speeds offered in Settings and in the player.
enum PlaybackSpeed {
    static let choices: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

    static func displayName(_ speed: Float) -> String {
        String(format: "%gx", speed)
    }
}
