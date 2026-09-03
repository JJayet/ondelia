import Foundation
import Translation

@MainActor
@Observable
final class TranslationManager {
    static let shared = TranslationManager()
    
    var isTranslating = false
    var translationProgress: Double = 0
    
    private let themeManager = ThemeManager.shared
    
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
    
    /// Translate transcription result using settings
    /// - Parameter transcriptionResult: The transcription to translate
    /// - Returns: Translated transcription result
    func translateTranscriptionResult(_ transcriptionResult: TranscriptionResult) async throws -> TranscriptionResult {
        guard themeManager.enableTranslation else {
            return transcriptionResult
        }
        
        let sourceLanguage = transcriptionResult.language
        let targetLanguage = themeManager.translationTargetLanguage.rawValue
        
        // Don't translate if source and target are the same
        guard sourceLanguage != targetLanguage else {
            return transcriptionResult
        }
        
        let translatedText = try await translateText(
            transcriptionResult.text,
            from: sourceLanguage,
            to: targetLanguage
        )
        
        // Translate segments individually
        var translatedSegments: [TranscriptionSegment] = []
        
        let totalSegments = transcriptionResult.segments.count
        
        for (index, segment) in transcriptionResult.segments.enumerated() {
            let translatedSegmentText = try await translateText(
                segment.text,
                from: sourceLanguage,
                to: targetLanguage
            )
            
            let translatedSegment = TranscriptionSegment(
                text: translatedSegmentText,
                start: segment.start,
                end: segment.end
            )
            
            translatedSegments.append(translatedSegment)
            
            translationProgress = Double(index + 1) / Double(totalSegments)
        }
        
        return TranscriptionResult(
            text: translatedText,
            segments: translatedSegments,
            language: targetLanguage
        )
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
