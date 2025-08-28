import Foundation
import Translation

@available(iOS 17.4, *)
class TranslationManager: ObservableObject {
    static let shared = TranslationManager()
    
    @Published var isTranslating = false
    @Published var translationProgress: Double = 0
    
    private let themeManager = ThemeManager.shared
    
    private init() {}
    
    // MARK: - Public Interface
    
    /// Translate text from one language to another
    /// - Parameters:
    ///   - text: The text to translate
    ///   - sourceLanguage: Source language code (e.g., "en")
    ///   - targetLanguage: Target language code (e.g., "es")
    /// - Returns: Translated text
    @available(iOS 17.4, *)
    func translateText(_ text: String, from sourceLanguage: String, to targetLanguage: String) async throws -> String {
        guard !text.isEmpty else { return text }
        
        await MainActor.run {
            isTranslating = true
            translationProgress = 0
        }
        
        defer {
            Task { @MainActor in
                isTranslating = false
                translationProgress = 0
            }
        }
        
        do {
            print("🔄 TranslationManager: Starting translation from \(sourceLanguage) to \(targetLanguage)")
            
            // Create translation session
            let configuration = TranslationSession.Configuration(
                source: Locale.Language(identifier: sourceLanguage),
                target: Locale.Language(identifier: targetLanguage)
            )
            
            let session = TranslationSession(configuration: configuration)
            
            await MainActor.run {
                translationProgress = 0.5
            }
            
            // Perform translation
            let request = TranslationSession.Request(sourceText: text)
            let response = try await session.translate(request)
            
            await MainActor.run {
                translationProgress = 1.0
            }
            
            print("✅ TranslationManager: Translation completed")
            return response.targetText
            
        } catch {
            print("❌ TranslationManager: Translation error: \(error)")
            throw TranslationError.translationFailed(error)
        }
    }
    
    /// Translate transcription result using settings
    /// - Parameter transcriptionResult: The transcription to translate
    /// - Returns: Translated transcription result
    @available(iOS 17.4, *)
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
            
            // Update progress
            await MainActor.run {
                translationProgress = Double(index + 1) / Double(totalSegments)
            }
        }
        
        return TranscriptionResult(
            text: translatedText,
            segments: translatedSegments,
            language: targetLanguage
        )
    }
    
    /// Check if translation is available for the given language pair
    /// - Parameters:
    ///   - sourceLanguage: Source language code
    ///   - targetLanguage: Target language code
    /// - Returns: Whether translation is available
    @available(iOS 17.4, *)
    func isTranslationAvailable(from sourceLanguage: String, to targetLanguage: String) async -> Bool {
        guard sourceLanguage != targetLanguage else { return true }
        
        // Simplified availability check - in a real implementation,
        // you would use LanguageAvailability
        return true
    }
    
    /// Get available translation language pairs
    /// - Returns: Array of supported language pairs
    @available(iOS 17.4, *)
    func getAvailableLanguagePairs() async -> [(source: TranscriptionLanguage, target: TranscriptionLanguage)] {
        var pairs: [(source: TranscriptionLanguage, target: TranscriptionLanguage)] = []
        
        for sourceLanguage in TranscriptionLanguage.allCases {
            for targetLanguage in TranscriptionLanguage.allCases {
                if sourceLanguage != targetLanguage {
                    let isAvailable = await isTranslationAvailable(
                        from: sourceLanguage.rawValue,
                        to: targetLanguage.rawValue
                    )
                    if isAvailable {
                        pairs.append((source: sourceLanguage, target: targetLanguage))
                    }
                }
            }
        }
        
        return pairs
    }
}

// MARK: - Error Types
enum TranslationError: Error, LocalizedError {
    case translationFailed(Error)
    case languageNotSupported
    case translationUnavailable
    
    var errorDescription: String? {
        switch self {
        case .translationFailed(let error):
            return "Translation failed: \(error.localizedDescription)"
        case .languageNotSupported:
            return "Language not supported for translation"
        case .translationUnavailable:
            return "Translation service unavailable"
        }
    }
}

// MARK: - iOS Version Compatibility
extension TranslationManager {
    static var isAvailable: Bool {
        if #available(iOS 17.4, *) {
            return true
        } else {
            return false
        }
    }
}