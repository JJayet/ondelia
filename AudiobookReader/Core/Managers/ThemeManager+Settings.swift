import SwiftUI

enum AppTheme: Int, CaseIterable {
    case system = 0
    case light = 1
    case dark = 2
    case sepia = 3
    case dim = 4
    
    var displayName: String {
        switch self {
        case .system: return NSLocalizedString("System", comment: "System appearance theme")
        case .light: return NSLocalizedString("Light", comment: "Light appearance theme")
        case .dark: return NSLocalizedString("Dark", comment: "Dark appearance theme")
        case .sepia: return NSLocalizedString("Sepia", comment: "Sepia appearance theme")
        case .dim: return NSLocalizedString("Dim", comment: "Dim appearance theme")
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        case .sepia: return .light
        case .dim: return .dark
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
    
    @MainActor var color: Color {
        // Base palette
        let base: Color = {
            switch self {
            case .blue: return .blue
            case .green: return .green
            case .orange: return .orange
            case .purple: return .purple
            case .red: return .red
            case .teal: return .teal
            }
        }()

        // Dim theme: slightly mute accents to reduce contrast
        if ThemeManager.shared.currentTheme == .dim {
            switch self {
            case .blue:   return Color(red: 0.36, green: 0.53, blue: 0.90)   // #5C87E5
            case .green:  return Color(red: 0.35, green: 0.76, blue: 0.54)   // #59C288
            case .orange: return Color(red: 0.94, green: 0.66, blue: 0.38)   // #F0A760
            case .purple: return Color(red: 0.69, green: 0.54, blue: 0.90)   // #B08AE6
            case .red:    return Color(red: 0.88, green: 0.41, blue: 0.41)   // #E06767
            case .teal:   return Color(red: 0.39, green: 0.76, blue: 0.76)   // #63C2C2
            }
        }

        return base
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

enum TranscriptionEngine: Int, CaseIterable {
    case whisperKit = 0
    
    var displayName: String {
        switch self {
        case .whisperKit: return "WhisperKit"
        }
    }
    
    var description: String {
        switch self {
        case .whisperKit:
            return NSLocalizedString(
                "On-device AI transcription with timestamps and translation",
                comment: "WhisperKit transcription engine description"
            )
        }
    }
}

enum WhisperModel: String, CaseIterable {
    case tiny = "openai_whisper-tiny"
    case base = "openai_whisper-base"
    case small = "openai_whisper-small"
    case medium = "openai_whisper-medium"
    case largeV3 = "openai_whisper-large-v3"
    
    var displayName: String {
        switch self {
        case .tiny: return NSLocalizedString("Tiny", comment: "Tiny Whisper model")
        case .base: return NSLocalizedString("Base", comment: "Base Whisper model")
        case .small: return NSLocalizedString("Small", comment: "Small Whisper model")
        case .medium: return NSLocalizedString("Medium", comment: "Medium Whisper model")
        case .largeV3: return NSLocalizedString("Large v3", comment: "Large Whisper model")
        }
    }
    
    var description: String {
        switch self {
        case .tiny: return NSLocalizedString("Fastest (~39 MB) - Basic accuracy", comment: "Tiny model description")
        case .base: return NSLocalizedString("Balanced (~74 MB) - Good accuracy", comment: "Base model description")
        case .small: return NSLocalizedString("Better (~244 MB) - High accuracy", comment: "Small model description")
        case .medium: return NSLocalizedString("High (~769 MB) - Very high accuracy", comment: "Medium model description")
        case .largeV3: return NSLocalizedString("Best (~1550 MB) - Highest accuracy", comment: "Large model description")
        }
    }
    
    var sizeDescription: String {
        switch self {
        case .tiny: return "39 MB"
        case .base: return "74 MB"
        case .small: return "244 MB"
        case .medium: return "769 MB"
        case .largeV3: return "1.5 GB"
        }
    }
    
    var speedRating: Int {
        switch self {
        case .tiny: return 5
        case .base: return 4
        case .small: return 3
        case .medium: return 2
        case .largeV3: return 1
        }
    }
    
    var accuracyRating: Int {
        switch self {
        case .tiny: return 2
        case .base: return 3
        case .small: return 4
        case .medium: return 4
        case .largeV3: return 5
        }
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
