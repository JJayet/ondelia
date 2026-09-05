import Foundation
import Translation

@MainActor
@Observable
final class TranslationManager {
    static let shared = TranslationManager()
    
    var isTranslating = false
    
    private init() {}
    
    // MARK: - Public Interface
    
    /// Translate text from one language to another
    /// - Parameters:
    ///   - text: The text to translate
    ///   - sourceLanguage: Source language code (e.g., "en")
    ///   - targetLanguage: Target language code (e.g., "es")
    /// - Returns: Translated text
    func translateText(_ text: String, from sourceLanguage: String, to targetLanguage: String) async throws -> String {
        guard !text.isEmpty else { return text }
        
        isTranslating = true
        defer { isTranslating = false }
        
        do {
            Log.transcription.debug("🔄 TranslationManager: Starting translation from \(sourceLanguage) to \(targetLanguage)")
            
            // Create translation session
            let session = TranslationSession(
                installedSource: Locale.Language(identifier: sourceLanguage),
                target: Locale.Language(identifier: targetLanguage)
            )
            
            try await session.prepareTranslation()
            
            // Perform translation
            let response = try await session.translate(text)
            
            Log.transcription.debug("✅ TranslationManager: Translation completed")
            return response.targetText
            
        } catch {
            Log.transcription.error("❌ TranslationManager: Translation error: \(error)")
            throw TranslationError.translationFailed(error)
        }
    }
    
}

// MARK: - Error Types
enum TranslationError: Error, LocalizedError {
    case translationFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .translationFailed(let error):
            return "Translation failed: \(error.localizedDescription)"
        }
    }
}
