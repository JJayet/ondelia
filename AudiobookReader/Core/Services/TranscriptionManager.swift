import Foundation
import Speech
import AVFoundation
import CoreData
import WhisperKit

class TranscriptionManager: ObservableObject {
    static let shared = TranscriptionManager()
    
    @Published var isTranscribing = false
    @Published var currentTranscription = ""
    @Published var transcriptionProgress: Double = 0
    @Published var isModelLoading = false
    @Published var modelLoadingProgress: Double = 0
        
    private let persistenceController = PersistenceController.shared
    private let themeManager = ThemeManager.shared
    private let whisperManager = WhisperTranscriptionManager.shared
    private var translationManager: AnyObject?
    
    deinit {
        stopTranscription()
    }
    
    var isReady: Bool {
        return whisperManager.isReady
    }
    
    // MARK: - Transcription Methods
    func transcribeAudioFile(_ audioURL: URL, for audiobook: Audiobook, chapterIndex: Int) async throws -> String {
        let transcriptionResult = try await transcribeAudioFileWithDetails(audioURL, for: audiobook, chapterIndex: chapterIndex)
        return transcriptionResult.text
    }
    
    func transcribeAudioFileWithDetails(_ audioURL: URL, for audiobook: Audiobook, chapterIndex: Int) async throws -> TranscriptionResult {
        await MainActor.run {
            isModelLoading = whisperManager.isModelLoading
            modelLoadingProgress = whisperManager.modelLoadingProgress
        }
        
        let result = try await whisperManager.transcribeAudioFile(audioURL, for: audiobook, chapterIndex: chapterIndex)
        
        if themeManager.enableTranslation && TranslationManager.isAvailable {
            if let translationManager = translationManager as? TranslationManager {
                return try await translationManager.translateTranscriptionResult(result)
            }
        }
        
        return result
    }
        
    func transcribeCurrentChapter(for audiobook: Audiobook, currentChapterIndex: Int) async throws -> String {
        await MainActor.run {
            isTranscribing = true
        }
        let result = try await transcribeCurrentChapterWithDetails(for: audiobook, currentChapterIndex: currentChapterIndex)
        return result.text
    }
    
    func transcribeCurrentChapterWithDetails(for audiobook: Audiobook, currentChapterIndex: Int) async throws -> TranscriptionResult {
        // Get the current chapter file URL
        guard let folderURL = audiobook.fileURL.map(URL.init(fileURLWithPath:)),
              let chapterFiles = getChapterFiles(from: folderURL),
              currentChapterIndex < chapterFiles.count else {
            throw TranscriptionError.chapterNotFound
        }
        
        let currentChapterURL = folderURL.appendingPathComponent(chapterFiles[currentChapterIndex])
        
        if let existingResult = getCachedTranscriptionResult(for: audiobook, chapterIndex: currentChapterIndex) {
            print("📖 TranscriptionManager: Using cached transcription")
            await MainActor.run {
                isTranscribing = false
                currentTranscription = existingResult.text
            }
            return existingResult
        }
        
        // Transcribe the audio file with details
        let transcriptionResult = try await transcribeAudioFileWithDetails(currentChapterURL, for: audiobook, chapterIndex: currentChapterIndex)
        
        // Cache the transcription result
        await cacheTranscriptionResult(transcriptionResult, for: audiobook, chapterIndex: currentChapterIndex)
        
        await MainActor.run {
            isTranscribing = false
        }
        return transcriptionResult
    }
    
    func stopTranscription() {
        DispatchQueue.main.async { [weak self] in
            self?.isTranscribing = false
        }
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
    private func getCachedTranscription(for audiobook: Audiobook, chapterIndex: Int) -> String? {
        return getCachedTranscriptionResult(for: audiobook, chapterIndex: chapterIndex)?.text
    }
    
    private func getCachedTranscriptionResult(for audiobook: Audiobook, chapterIndex: Int) -> TranscriptionResult? {
        let context = persistenceController.context
        let request: NSFetchRequest<ChapterTranscription> = ChapterTranscription.fetchRequest()
        request.predicate = NSPredicate(format: "audiobook == %@ AND chapterIndex == %d", audiobook, chapterIndex)
        
        do {
            let transcriptions = try context.fetch(request)
            guard let cached = transcriptions.first,
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
        } catch {
            print("❌ TranscriptionManager: Error fetching cached transcription: \(error)")
            return nil
        }
    }
    
    private func cacheTranscription(_ text: String, for audiobook: Audiobook, chapterIndex: Int) async {
        // Create a simple TranscriptionResult for backward compatibility
        let result = TranscriptionResult(
            text: text,
            segments: [],
            language: themeManager.transcriptionLanguage.rawValue
        )
        await cacheTranscriptionResult(result, for: audiobook, chapterIndex: chapterIndex)
    }
    
    private func cacheTranscriptionResult(_ result: TranscriptionResult, for audiobook: Audiobook, chapterIndex: Int) async {
        let audiobookObjectID = audiobook.objectID
        await MainActor.run {
            let context = persistenceController.context
            guard let audiobook = try? context.existingObject(with: audiobookObjectID) as? Audiobook else {
                print("❌ TranscriptionManager: Failed to find audiobook for caching")
                return
            }
            
            // Remove existing transcription if any
            let request: NSFetchRequest<ChapterTranscription> = ChapterTranscription.fetchRequest()
            request.predicate = NSPredicate(format: "audiobook == %@ AND chapterIndex == %d", audiobook, chapterIndex)
            
            if let existingTranscription = try? context.fetch(request).first {
                context.delete(existingTranscription)
            }
            
            // Create new transcription
            let transcription = ChapterTranscription(context: context)
            transcription.id = UUID()
            transcription.audiobook = audiobook
            transcription.chapterIndex = Int16(chapterIndex)
            transcription.transcriptionText = result.text
            transcription.language = result.language
            transcription.transcriptionEngine = themeManager.transcriptionEngine.displayName
            transcription.dateCreated = Date()
            
            // Store segments as JSON data
            if !result.segments.isEmpty {
                transcription.segmentsData = try? JSONEncoder().encode(result.segments)
            }
            
            persistenceController.save()
            print("💾 TranscriptionManager: Cached transcription for chapter \(chapterIndex)")
        }
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
