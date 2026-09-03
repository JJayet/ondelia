import Foundation
import Speech
import AVFoundation
import SwiftData

@MainActor
@Observable
final class TranscriptionManager {
    static let shared = TranscriptionManager()
    
    var isTranscribing = false
    var currentTranscription = ""
    var transcriptionProgress: Double = 0
    var isModelLoading = false
    var modelLoadingProgress: Double = 0
        
    private let swiftDataController = SwiftDataController.shared
    private var transcriptionStore: TranscriptionStore?
    private let themeManager = ThemeManager.shared
    private let speechManager = SpeechTranscriptionManager.shared
    private let translationManager = TranslationManager.shared
    
    deinit {
        // Avoid calling @MainActor methods during deinit
    }
    
    var isReady: Bool {
        return speechManager.isReady
    }

    /// Built on first use: reading `container` before the store has loaded would trap.
    private func store() -> TranscriptionStore? {
        guard swiftDataController.isLoaded else { return nil }
        if let transcriptionStore { return transcriptionStore }
        let store = TranscriptionStore(modelContainer: swiftDataController.container)
        transcriptionStore = store
        return store
    }
    
    // MARK: - Transcription Methods
    func transcribeAudioFile(_ audioURL: URL, for audiobook: AudiobookModel, chapterIndex: Int) async throws -> String {
        let transcriptionResult = try await transcribeAudioFileWithDetails(audioURL, for: audiobook, chapterIndex: chapterIndex)
        return transcriptionResult.text
    }
    
    func transcribeAudioFileWithDetails(_ audioURL: URL, for audiobook: AudiobookModel, chapterIndex: Int) async throws -> TranscriptionResult {
        isModelLoading = speechManager.isModelLoading
        modelLoadingProgress = speechManager.modelLoadingProgress

        let result = try await speechManager.transcribeAudioFile(audioURL, for: audiobook, chapterIndex: chapterIndex)
        
        guard themeManager.enableTranslation else { return result }
        return try await translationManager.translateTranscriptionResult(result)
    }
        
    func transcribeCurrentChapter(for audiobook: AudiobookModel, currentChapterIndex: Int) async throws -> String {
        await MainActor.run {
            isTranscribing = true
        }
        let result = try await transcribeCurrentChapterWithDetails(for: audiobook, currentChapterIndex: currentChapterIndex)
        return result.text
    }
    
    func transcribeCurrentChapterWithDetails(for audiobook: AudiobookModel, currentChapterIndex: Int) async throws -> TranscriptionResult {
        // Get the current chapter file URL
        guard let folderURL = audiobook.resolvedFileURL,
              let chapterFiles = getChapterFiles(from: folderURL),
              currentChapterIndex < chapterFiles.count else {
            throw TranscriptionError.chapterNotFound
        }
        
        let currentChapterURL: URL
        do {
            currentChapterURL = try SafeImportPath.containedFileURL(
                for: chapterFiles[currentChapterIndex],
                inside: folderURL
            )
        } catch {
            throw TranscriptionError.chapterNotFound
        }
        
        let audiobookID = audiobook.id
        let chapter = Int16(currentChapterIndex)

        if let existingResult = await store()?.cachedResult(audiobookID: audiobookID, chapterIndex: chapter) {
            Log.transcription.debug("📖 TranscriptionManager: Using cached transcription")
            await MainActor.run {
                isTranscribing = false
                currentTranscription = existingResult.text
            }
            return existingResult
        }
        
        // Transcribe the audio file with details
        let transcriptionResult = try await transcribeAudioFileWithDetails(currentChapterURL, for: audiobook, chapterIndex: currentChapterIndex)
        
        await store()?.save(
            transcriptionResult,
            audiobookID: audiobookID,
            chapterIndex: chapter,
            engine: "SpeechAnalyzer"
        )

        isTranscribing = false
        return transcriptionResult
    }
    
    func stopTranscription() {
        isTranscribing = false
    }
    
    // MARK: - Helper Methods
    private func getChapterFiles(from folderURL: URL) -> [String]? {
        let manifestURL = folderURL.appendingPathComponent("audiobook_manifest.json")
        
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let chaptersData = manifest["chapters"] as? [[String: Any]] else {
            return nil
        }
        
        return chaptersData.compactMap { $0["fileName"] as? String }
    }
    
}

// MARK: - Error Types
enum TranscriptionError: Error, LocalizedError {
    case authorizationDenied
    case recognizerUnavailable
    case chapterNotFound
    case transcriptionFailed
    
    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Speech recognition authorization denied"
        case .recognizerUnavailable:
            return "Speech recognizer unavailable"
        case .chapterNotFound:
            return "Chapter file not found"
        case .transcriptionFailed:
            return "Transcription failed"
        }
    }
}
