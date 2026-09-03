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
