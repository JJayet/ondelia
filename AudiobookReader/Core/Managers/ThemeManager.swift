import SwiftUI
import Combine

class ThemeManager: ObservableObject {
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
        // Load settings asynchronously to avoid blocking initialization
        DispatchQueue.global(qos: .utility).async {
            self.loadSettings()
        }
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
        
        // Update published properties on main queue
        DispatchQueue.main.async {
            self.currentTheme = theme
            self.accentColor = accent
            self.skipInterval = skip
            self.transcriptionEngine = engine
            self.whisperModel = model
            self.transcriptionLanguage = language
            self.enableTranslation = translation
            self.translationTargetLanguage = targetLanguage
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
    
    // MARK: - Transcription Settings
    func updateTranscriptionEngine(_ engine: TranscriptionEngine) {
        transcriptionEngine = engine
        UserDefaults.standard.set(engine.rawValue, forKey: "transcriptionEngine")
        
        // Auto-download current model when switching to WhisperKit
        if engine == .whisperKit {
            Task {
                do {
                    try await WhisperTranscriptionManager.shared.switchModel(to: whisperModel)
                } catch {
                    print("❌ Failed to switch WhisperKit model: \(error)")
                }
            }
        }
    }
    
    func updateWhisperModel(_ model: WhisperModel) {
        whisperModel = model
        UserDefaults.standard.set(model.rawValue, forKey: "whisperModel")
        
        // Trigger model download if WhisperKit engine is selected
        if transcriptionEngine == .whisperKit {
            Task {
                do {
                    try await WhisperTranscriptionManager.shared.switchModel(to: model)
                } catch {
                    print("❌ Failed to download WhisperKit model: \(error)")
                }
            }
        }
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