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
    private let themeManager = ThemeManager.shared
    private let speechManager = SpeechTranscriptionManager.shared
    private let translationManager = TranslationManager.shared
    
    deinit {
        // Avoid calling @MainActor methods during deinit
    }
    
    var isReady: Bool {
        return speechManager.isReady
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
            currentChapterURL = try SafeImportPath.existingFileURL(
                for: chapterFiles[currentChapterIndex],
                inside: folderURL
            )
        } catch {
            throw TranscriptionError.chapterNotFound
        }
        
        if let existingResult = await MainActor.run(body: { getCachedTranscriptionResult(audiobookID: audiobook.id, chapterIndex: Int16(currentChapterIndex)) }) {
            Log.transcription.debug("📖 TranscriptionManager: Using cached transcription")
            await MainActor.run {
                isTranscribing = false
                currentTranscription = existingResult.text
            }
            return existingResult
        }
        
        // Transcribe the audio file with details
        let transcriptionResult = try await transcribeAudioFileWithDetails(currentChapterURL, for: audiobook, chapterIndex: currentChapterIndex)
        
        // Cache the transcription result
        await cacheTranscriptionResult(transcriptionResult, for: audiobook, chapterIndex: Int16(currentChapterIndex))
        
        await MainActor.run {
            isTranscribing = false
        }
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
    
    // MARK: - Caching
    @MainActor private func getCachedTranscriptionResult(audiobookID: UUID, chapterIndex: Int16) -> TranscriptionResult? {
        let context = swiftDataController.context
        var descriptor = FetchDescriptor<ChapterTranscriptionModel>(
            predicate: #Predicate { transcription in
                transcription.chapterIndex == chapterIndex
                    && transcription.audiobook?.id == audiobookID
            }
        )
        descriptor.fetchLimit = 1

        let matches: [ChapterTranscriptionModel]
        do {
            matches = try context.fetch(descriptor)
        } catch {
            Log.transcription.error("❌ TranscriptionManager: Error fetching transcriptions: \(error)")
            return nil
        }
        
        guard let cached = matches.first,
              let text = cached.transcriptionText else {
            return nil
        }
            
            // Parse segments if available
            var segments: [TranscriptionSegment] = []
            if let segmentsData = cached.segmentsData,
               let segmentArray = try? JSONDecoder().decode([TranscriptionSegment].self, from: segmentsData) {
                segments = segmentArray
            }
            
            return TranscriptionResult(
                text: text,
                segments: segments,
                language: cached.language ?? "en"
            )
    }
    
    @MainActor
    private func cacheTranscriptionResult(_ result: TranscriptionResult, for audiobook: AudiobookModel, chapterIndex: Int16) async {
        let context = swiftDataController.context
        
        // Remove existing transcription if any
        let audiobookID = audiobook.id
        var existingDescriptor = FetchDescriptor<ChapterTranscriptionModel>(
            predicate: #Predicate { transcription in
                transcription.chapterIndex == chapterIndex
                    && transcription.audiobook?.id == audiobookID
            }
        )
        existingDescriptor.fetchLimit = 1
        if let existingTranscription = try? context.fetch(existingDescriptor).first {
            context.delete(existingTranscription)
        }
        
        // Create new transcription
        let transcription = ChapterTranscriptionModel(
            chapterIndex: chapterIndex,
            transcriptionText: result.text,
            language: result.language,
            transcriptionEngine: "SpeechAnalyzer",
            dateCreated: Date()
        )
        transcription.audiobook = audiobook
        
        // Store segments as JSON data
        if !result.segments.isEmpty {
            transcription.segmentsData = try? JSONEncoder().encode(result.segments)
        }
        
        context.insert(transcription)
        swiftDataController.save()
        Log.transcription.debug("💾 TranscriptionManager: Cached transcription for chapter \(chapterIndex)")
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
