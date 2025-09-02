import SwiftUI
import Combine

@MainActor
class ThemeManager: ThemeManagerProtocol {    
    static let shared = ThemeManager()
    
    @Published var currentTheme: AppTheme = .system
    @Published var accentColor: AccentColor = .blue
    @Published var skipInterval: SkipInterval = .fifteen
    
    // Transcription Settings
    @Published var transcriptionEngine: TranscriptionEngine = .whisperKit
    @Published var whisperModel: WhisperModel = .base
    @Published var transcriptionLanguage: TranscriptionLanguage = .english
    @Published var enableTranslation: Bool = false
    @Published var translationTargetLanguage: TranscriptionLanguage = .english
    
    private init() {
        // Load settings without GCD to align with @MainActor
        Task { self.loadSettings() }
    }
    
    private func loadSettings() {
        let theme: AppTheme
        let accent: AccentColor
        let skip: SkipInterval
        let engine: TranscriptionEngine
        let model: WhisperModel
        let language: TranscriptionLanguage
        let translation: Bool
        let targetLanguage: TranscriptionLanguage
        
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
        
        // Transcription settings
        if let engineRawValue = UserDefaults.standard.object(forKey: "transcriptionEngine") as? Int,
           let loadedEngine = TranscriptionEngine(rawValue: engineRawValue) {
            engine = loadedEngine
        } else {
            engine = .whisperKit
        }
        
        if let modelRawValue = UserDefaults.standard.object(forKey: "whisperModel") as? String,
           let loadedModel = WhisperModel(rawValue: modelRawValue) {
            model = loadedModel
        } else {
            model = .base
        }
        
        if let languageRawValue = UserDefaults.standard.object(forKey: "transcriptionLanguage") as? String,
           let loadedLanguage = TranscriptionLanguage(rawValue: languageRawValue) {
            language = loadedLanguage
        } else {
            language = .english
        }
        
        translation = UserDefaults.standard.bool(forKey: "enableTranslation")
        
        if let targetLanguageRawValue = UserDefaults.standard.object(forKey: "translationTargetLanguage") as? String,
           let loadedTargetLanguage = TranscriptionLanguage(rawValue: targetLanguageRawValue) {
            targetLanguage = loadedTargetLanguage
        } else {
            targetLanguage = .english
        }
        
        // Update published properties on main actor
        self.currentTheme = theme
        self.accentColor = accent
        self.skipInterval = skip
        self.transcriptionEngine = engine
        self.whisperModel = model
        self.transcriptionLanguage = language
        self.enableTranslation = translation
        self.translationTargetLanguage = targetLanguage
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
    }
    
    // MARK: - Transcription Settings
    func updateTranscriptionEngine(_ engine: TranscriptionEngine) {
        transcriptionEngine = engine
        UserDefaults.standard.set(engine.rawValue, forKey: "transcriptionEngine")
    }
    
    func updateWhisperModel(_ model: WhisperModel) {
        whisperModel = model
        UserDefaults.standard.set(model.rawValue, forKey: "whisperModel")
    }
    
    func updateTranscriptionLanguage(_ language: TranscriptionLanguage) {
        transcriptionLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: "transcriptionLanguage")
    }
    
    func updateEnableTranslation(_ enabled: Bool) {
        enableTranslation = enabled
        UserDefaults.standard.set(enabled, forKey: "enableTranslation")
    }
    
    func updateTranslationTargetLanguage(_ language: TranscriptionLanguage) {
        translationTargetLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: "translationTargetLanguage")
    }
}

enum AppTheme: Int, CaseIterable {
    case system = 0
    case light = 1
    case dark = 2
    case sepia = 3
    case dim = 4
    
    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .sepia: return "Sepia"
        case .dim: return "Dim"
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
        case .blue: return "Blue"
        case .green: return "Green"
        case .orange: return "Orange"
        case .purple: return "Purple"
        case .red: return "Red"
        case .teal: return "Teal"
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
        case .whisperKit: return "On-device AI transcription with timestamps and translation"
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
        case .tiny: return "Tiny"
        case .base: return "Base"
        case .small: return "Small"
        case .medium: return "Medium"
        case .largeV3: return "Large v3"
        }
    }
    
    var description: String {
        switch self {
        case .tiny: return "Fastest (~39 MB) - Basic accuracy"
        case .base: return "Balanced (~74 MB) - Good accuracy"
        case .small: return "Better (~244 MB) - High accuracy"
        case .medium: return "High (~769 MB) - Very high accuracy"
        case .largeV3: return "Best (~1550 MB) - Highest accuracy"
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
        case .english: return "English"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        case .italian: return "Italian"
        case .portuguese: return "Portuguese"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .chinese: return "Chinese"
        }
    }
    
    var locale: Locale {
        return Locale(identifier: rawValue)
    }
}

// MARK: - Theme Environment
struct ThemeEnvironment: EnvironmentKey {
    @MainActor
    static var defaultValue: ThemeManager { ThemeManager.shared }
}

extension EnvironmentValues {
    var theme: ThemeManager {
        get { self[ThemeEnvironment.self] }
        set { self[ThemeEnvironment.self] = newValue }
    }
}

// MARK: - Custom Colors
extension Color {
    @MainActor static var primaryBackground: Color {
        switch ThemeManager.shared.currentTheme {
        case .sepia:
            // Sepia: warm parchment
            return Color(red: 0.953, green: 0.914, blue: 0.843) // #F3E9D7
        case .dark:
            return Color(red: 0.06, green: 0.06, blue: 0.07)
        case .dim:
            // Dim: softer dark, less contrast than pure dark
            return Color(red: 0.106, green: 0.110, blue: 0.122) // #1B1C1F
        case .light:
            return Color(.systemBackground)
        case .system:
            return Color(.systemBackground)
        }
    }

    // Glass tint to theme materials consistently
    @MainActor static var glassTint: Color {
        switch ThemeManager.shared.currentTheme {
        case .sepia:
            // Warm amber glow over material
            return Color(red: 0.90, green: 0.74, blue: 0.42).opacity(0.10) // #E6BD6B @10%
        case .dim:
            // Slight lift to avoid harsh contrast
            return Color.white.opacity(0.06)
        case .dark:
            return Color.white.opacity(0.04)
        case .light, .system:
            return Color.black.opacity(0.03)
        }
    }
    
    @MainActor static var secondaryBackground: Color {
        switch ThemeManager.shared.currentTheme {
        case .sepia:
            return Color(red: 0.937, green: 0.882, blue: 0.788) // #EFE1C9
        case .dark:
            return Color(red: 0.10, green: 0.10, blue: 0.11)
        case .dim:
            return Color(red: 0.137, green: 0.145, blue: 0.161) // #232529
        case .light:
            return Color(.systemGroupedBackground)
        case .system:
            return Color(.systemGroupedBackground)
        }
    }
    
    @MainActor static var primaryText: Color {
        switch ThemeManager.shared.currentTheme {
        case .sepia:
            return Color(red: 0.243, green: 0.184, blue: 0.118) // #3E2F1E
        case .dark, .dim:
            return Color(red: 0.903, green: 0.909, blue: 0.915) // #E6E7EA
        case .light, .system:
            return Color(.label)
        }
    }
    
    @MainActor static var secondaryText: Color {
        switch ThemeManager.shared.currentTheme {
        case .sepia:
            return Color(red: 0.435, green: 0.353, blue: 0.235) // #6F5A3C
        case .dark, .dim:
            return Color(red: 0.659, green: 0.671, blue: 0.698) // #A8ABB2
        case .light, .system:
            return Color(.secondaryLabel)
        }
    }
}

// MARK: - Dynamic Type Typography System
extension Font {
    // Display fonts for large content
    static var displayLarge: Font {
        .custom("SF Pro Display", size: 57, relativeTo: .largeTitle)
    }
    
    static var displayMedium: Font {
        .custom("SF Pro Display", size: 45, relativeTo: .largeTitle)
    }
    
    static var displaySmall: Font {
        .custom("SF Pro Display", size: 36, relativeTo: .title)
    }
    
    // Headline fonts for section headers
    static var headlineLarge: Font {
        .custom("SF Pro Display", size: 32, relativeTo: .title)
    }
    
    static var headlineMedium: Font {
        .custom("SF Pro Display", size: 28, relativeTo: .title2)
    }
    
    static var headlineSmall: Font {
        .custom("SF Pro Display", size: 24, relativeTo: .title3)
    }
    
    // Title fonts for content headers
    static var titleLarge: Font {
        .custom("SF Pro Text", size: 22, relativeTo: .headline)
    }
    
    static var titleMedium: Font {
        .custom("SF Pro Text", size: 16, relativeTo: .body)
    }
    
    static var titleSmall: Font {
        .custom("SF Pro Text", size: 14, relativeTo: .subheadline)
    }
    
    // Label fonts for UI elements
    static var labelLarge: Font {
        .custom("SF Pro Text", size: 14, relativeTo: .footnote)
    }
    
    static var labelMedium: Font {
        .custom("SF Pro Text", size: 12, relativeTo: .caption)
    }
    
    static var labelSmall: Font {
        .custom("SF Pro Text", size: 11, relativeTo: .caption2)
    }
    
    // Body fonts with enhanced readability
    static var bodyLarge: Font {
        .custom("SF Pro Text", size: 16, relativeTo: .body)
    }
    
    static var bodyMedium: Font {
        .custom("SF Pro Text", size: 14, relativeTo: .callout)
    }
    
    static var bodySmall: Font {
        .custom("SF Pro Text", size: 12, relativeTo: .footnote)
    }
}
