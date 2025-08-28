import Foundation
import WhisperKit
import AVFoundation
import CoreData

class WhisperTranscriptionManager: ObservableObject {
    static let shared = WhisperTranscriptionManager()
    
    @Published var isTranscribing = false
    @Published var currentTranscription = ""
    @Published var transcriptionProgress: Double = 0
    @Published var isModelLoading = false
    @Published var modelLoadingProgress: Double = 0
    
    private var whisperKit: WhisperKit?
    private let persistenceController = PersistenceController.shared
    private let themeManager = ThemeManager.shared
    
    // Current model name tracking
    private var currentModelName: String = ""
    
    private init() {
        Task {
            await initializeWhisperKit()
        }
    }
    
    // MARK: - Initialization
    @MainActor
    private func initializeWhisperKit() async {
        let selectedModel = themeManager.whisperModel.rawValue
        currentModelName = selectedModel
        
        isModelLoading = true
        modelLoadingProgress = 0
        
        do {
            print("🤖 WhisperTranscriptionManager: Initializing WhisperKit with model \(selectedModel)...")
            
            // Initialize with progress callback
            whisperKit = try await WhisperKit(
                model: selectedModel,
                prewarm: true,
                load: true,
                download: true
            )
            
            isModelLoading = false
            modelLoadingProgress = 1.0
            print("✅ WhisperTranscriptionManager: WhisperKit initialized successfully")
            
        } catch {
            print("❌ WhisperTranscriptionManager: Failed to initialize WhisperKit: \(error)")
            isModelLoading = false
        }
    }
    
    // MARK: - Public Interface
    var isReady: Bool {
        return whisperKit != nil && !isModelLoading
    }
    
    // Check if model needs switching
    func needsModelSwitch() -> Bool {
        return currentModelName != themeManager.whisperModel.rawValue
    }
    
    // Switch model if needed
    func switchModelIfNeeded() async throws {
        if needsModelSwitch() {
            try await switchModel(to: themeManager.whisperModel)
        }
    }
    
    func transcribeAudioFile(_ audioURL: URL, for audiobook: Audiobook, chapterIndex: Int) async throws -> TranscriptionResult {
        // Check if model switch is needed
        try await switchModelIfNeeded()
        
        guard let whisperKit = whisperKit else {
            throw WhisperTranscriptionError.whisperKitNotInitialized
        }
        
        print("🎤 WhisperTranscriptionManager: Starting transcription for chapter \(chapterIndex)")
        
        await MainActor.run {
            isTranscribing = true
            transcriptionProgress = 0
        }
        
        defer {
            Task { @MainActor in
                isTranscribing = false
                transcriptionProgress = 0
            }
        }
        
        // Ensure we have access to the security-scoped resource
        let hasAccess = audioURL.startAccessingSecurityScopedResource()
        defer { 
            if hasAccess { 
                audioURL.stopAccessingSecurityScopedResource() 
            }
        }
        
        do {
            // Get audio duration for progress calculation
            let asset = AVURLAsset(url: audioURL)
            let audioDuration = try await asset.load(.duration).seconds
            
            // Start transcription using simplified API
            let result = try await whisperKit.transcribe(audioPath: audioURL.path)
            
            await MainActor.run {
                transcriptionProgress = 0.8
            }
            
            await MainActor.run {
                transcriptionProgress = 1.0
            }
            
            let finalTranscription = result.first?.text ?? ""
            var segments: [TranscriptionSegment] = []
            
            // In a full implementation, you would extract segments from result segments
            // For now, create a simple segment covering the entire audio
            if !finalTranscription.isEmpty {
                segments = [TranscriptionSegment(
                    text: finalTranscription,
                    start: 0.0,
                    end: audioDuration
                )]
            }
            
            await MainActor.run {
                currentTranscription = finalTranscription
            }
            
            print("✅ WhisperTranscriptionManager: Transcription completed")
            
            // Create transcription result with timestamps
            return TranscriptionResult(
                text: finalTranscription,
                segments: segments,
                language: themeManager.transcriptionLanguage.rawValue
            )
            
        } catch {
            print("❌ WhisperTranscriptionManager: Transcription error: \(error)")
            throw WhisperTranscriptionError.transcriptionFailed(error)
        }
    }
    
    func transcribeCurrentChapter(for audiobook: Audiobook, currentChapterIndex: Int) async throws -> TranscriptionResult {
        // Get the current chapter file URL
        guard let folderURL = audiobook.fileURL.map(URL.init(fileURLWithPath:)),
              let chapterFiles = getChapterFiles(from: folderURL),
              currentChapterIndex < chapterFiles.count else {
            throw WhisperTranscriptionError.chapterNotFound
        }
        
        let currentChapterURL = folderURL.appendingPathComponent(chapterFiles[currentChapterIndex])
        
        // Check if transcription already exists
        if let existingResult = getCachedTranscription(for: audiobook, chapterIndex: currentChapterIndex) {
            print("📖 WhisperTranscriptionManager: Using cached transcription")
            await MainActor.run {
                currentTranscription = existingResult.text
            }
            return existingResult
        }
        
        // Transcribe the audio file
        let transcriptionResult = try await transcribeAudioFile(currentChapterURL, for: audiobook, chapterIndex: currentChapterIndex)
        
        // Cache the transcription
        await cacheTranscription(transcriptionResult, for: audiobook, chapterIndex: currentChapterIndex)
        
        return transcriptionResult
    }
    
    func stopTranscription() {
        // Note: WhisperKit doesn't support stopping mid-transcription in the current API
        // But we can reset our state
        DispatchQueue.main.async { [weak self] in
            self?.isTranscribing = false
            self?.transcriptionProgress = 0
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
    
    // MARK: - Caching (reuse existing Core Data logic)
    private func getCachedTranscription(for audiobook: Audiobook, chapterIndex: Int) -> TranscriptionResult? {
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
            print("❌ WhisperTranscriptionManager: Error fetching cached transcription: \(error)")
            return nil
        }
    }
    
    private func cacheTranscription(_ result: TranscriptionResult, for audiobook: Audiobook, chapterIndex: Int) async {
        let audiobookObjectID = audiobook.objectID
        await MainActor.run {
            let context = persistenceController.context
            guard let audiobook = try? context.existingObject(with: audiobookObjectID) as? Audiobook else {
                print("❌ WhisperTranscriptionManager: Failed to find audiobook for caching")
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
            transcription.dateCreated = Date()
            
            // Store segments as JSON data
            if !result.segments.isEmpty {
                transcription.segmentsData = try? JSONEncoder().encode(result.segments)
            }
            
            persistenceController.save()
            print("💾 WhisperTranscriptionManager: Cached transcription for chapter \(chapterIndex)")
        }
    }
//}
//
//// MARK: - Error Types
//enum WhisperTranscriptionError: Error, LocalizedError {
//    case whisperKitNotInitialized
//    case chapterNotFound
//    case transcriptionFailed(Error)
//    case modelLoadingFailed
//    
//    var errorDescription: String? {
//        switch self {
//        case .whisperKitNotInitialized:
//            return "WhisperKit not initialized. Please wait for model to load."
//        case .chapterNotFound:
//            return "Chapter file not found"
//        case .transcriptionFailed(let error):
//            return "Transcription failed: \(error.localizedDescription)"
//        case .modelLoadingFailed:
//            return "Model loading failed"
//        }
    
    // MARK: - Model Management
    func switchModel(to model: WhisperModel) async throws {
        await MainActor.run {
            isModelLoading = true
            modelLoadingProgress = 0
        }
        
        do {
            whisperKit = try await WhisperKit(
                model: model.rawValue,
                prewarm: true,
                load: true,
                download: true
            )
            
            currentModelName = model.rawValue
            
            await MainActor.run {
                isModelLoading = false
                modelLoadingProgress = 1.0
            }
            
        } catch {
            await MainActor.run {
                isModelLoading = false
            }
            throw WhisperTranscriptionError.modelLoadingFailed
        }
    }
    
    // Get available models
    func getAvailableModels() -> [WhisperModel] {
        return WhisperModel.allCases
    }
}

// MARK: - Data Structures
struct TranscriptionResult {
    let text: String
    let segments: [TranscriptionSegment]
    let language: String
}

struct TranscriptionSegment: Codable {
    let text: String
    let start: Double
    let end: Double
}

// MARK: - Error Types
enum WhisperTranscriptionError: Error, LocalizedError {
    case whisperKitNotInitialized
    case chapterNotFound
    case transcriptionFailed(Error)
    case modelLoadingFailed
    
    var errorDescription: String? {
        switch self {
        case .whisperKitNotInitialized:
            return "WhisperKit not initialized. Please wait for model to load."
        case .chapterNotFound:
            return "Chapter file not found"
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        case .modelLoadingFailed:
            return "Model loading failed"
        }
    }
}
