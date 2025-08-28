//import Foundation
//import WhisperKit
//import AVFoundation
//import CoreData
//
//class WhisperTranscriptionManager: ObservableObject {
//    static let shared = WhisperTranscriptionManager()
//    
//    @Published var isTranscribing = false
//    @Published var currentTranscription = ""
//    @Published var transcriptionProgress: Double = 0
//    @Published var isModelLoading = false
//    @Published var modelLoadingProgress: Double = 0
//    
//    private var whisperKit: WhisperKit?
//    private let persistenceController = PersistenceController.shared
//    
//    // Model configuration
//    private let modelName = "openai_whisper-base" // Balance between speed and accuracy
//    
//    private init() {
//        Task {
//            await initializeWhisperKit()
//        }
//    }
//    
//    // MARK: - Initialization
//    @MainActor
//    private func initializeWhisperKit() async {
//        isModelLoading = true
//        modelLoadingProgress = 0
//        
//        do {
//            print("🤖 WhisperTranscriptionManager: Initializing WhisperKit...")
//            
//            // Initialize with progress callback
//            whisperKit = try await WhisperKit(
//                model: modelName,
//                download: true,
//                modelRepo: nil,
//                downloadBase: nil,
//                modelFolder: nil,
//                computeUnits: .all,
//                audioProcessor: nil,
//                featureExtractor: nil,
//                audioEncoder: nil,
//                textDecoder: nil,
//                logLevel: .info,
//                prewarm: true,
//                load: true,
//                download: true
//            ) { progress in
//                Task { @MainActor in
//                    self.modelLoadingProgress = progress.fractionCompleted
//                    print("📥 Model loading progress: \(Int(progress.fractionCompleted * 100))%")
//                }
//            }
//            
//            isModelLoading = false
//            modelLoadingProgress = 1.0
//            print("✅ WhisperTranscriptionManager: WhisperKit initialized successfully")
//            
//        } catch {
//            print("❌ WhisperTranscriptionManager: Failed to initialize WhisperKit: \(error)")
//            isModelLoading = false
//        }
//    }
//    
//    // MARK: - Public Interface
//    var isReady: Bool {
//        return whisperKit != nil && !isModelLoading
//    }
//    
//    func transcribeAudioFile(_ audioURL: URL, for audiobook: Audiobook, chapterIndex: Int) async throws -> String {
//        guard let whisperKit = whisperKit else {
//            throw WhisperTranscriptionError.whisperKitNotInitialized
//        }
//        
//        print("🎤 WhisperTranscriptionManager: Starting transcription for chapter \(chapterIndex)")
//        
//        await MainActor.run {
//            isTranscribing = true
//            transcriptionProgress = 0
//        }
//        
//        defer {
//            Task { @MainActor in
//                isTranscribing = false
//                transcriptionProgress = 0
//            }
//        }
//        
//        // Ensure we have access to the security-scoped resource
//        let hasAccess = audioURL.startAccessingSecurityScopedResource()
//        defer { 
//            if hasAccess { 
//                audioURL.stopAccessingSecurityScopedResource() 
//            }
//        }
//        
//        do {
//            // Get audio duration for progress calculation
//            let asset = AVURLAsset(url: audioURL)
//            let audioDuration = try await asset.load(.duration).seconds
//            
//            // Configure transcription options
//            let options = DecodingOptions(
//                verbose: true,
//                task: .transcribe,
//                language: "en", // You can make this configurable
//                temperature: 0.0,
//                temperatureFallbackCount: 0,
//                sampleLength: 224,
//                usePrefillPrompt: true,
//                usePrefillCache: true,
//                skipSpecialTokens: true,
//                withoutTimestamps: false,
//                wordTimestamps: true,
//                clipTimestamps: []
//            )
//            
//            // Start transcription with progress callback
//            let result = try await whisperKit.transcribe(
//                audioPath: audioURL.path,
//                decodeOptions: options,
//                callback: { [weak self] progress in
//                    Task { @MainActor in
//                        guard let self = self else { return }
//                        self.transcriptionProgress = progress.timings.totalDecodingLoops > 0 
//                            ? min(0.95, Double(progress.timings.totalDecodingLoops) / Double(audioDuration * 0.1))
//                            : 0.1
//                        
//                        // Update current transcription with partial results
//                        if let segments = progress.text, !segments.isEmpty {
//                            self.currentTranscription = segments.joined(separator: " ")
//                        }
//                    }
//                }
//            )
//            
//            await MainActor.run {
//                transcriptionProgress = 1.0
//            }
//            
//            let finalTranscription = result?.text ?? ""
//            
//            await MainActor.run {
//                currentTranscription = finalTranscription
//            }
//            
//            print("✅ WhisperTranscriptionManager: Transcription completed")
//            return finalTranscription
//            
//        } catch {
//            print("❌ WhisperTranscriptionManager: Transcription error: \(error)")
//            throw WhisperTranscriptionError.transcriptionFailed(error)
//        }
//    }
//    
//    func transcribeCurrentChapter(for audiobook: Audiobook, currentChapterIndex: Int) async throws -> String {
//        // Get the current chapter file URL
//        guard let folderURL = audiobook.fileURL.map(URL.init(fileURLWithPath:)),
//              let chapterFiles = getChapterFiles(from: folderURL),
//              currentChapterIndex < chapterFiles.count else {
//            throw WhisperTranscriptionError.chapterNotFound
//        }
//        
//        let currentChapterURL = folderURL.appendingPathComponent(chapterFiles[currentChapterIndex])
//        
//        // Check if transcription already exists
//        if let existingTranscription = getCachedTranscription(for: audiobook, chapterIndex: currentChapterIndex) {
//            print("📖 WhisperTranscriptionManager: Using cached transcription")
//            await MainActor.run {
//                currentTranscription = existingTranscription
//            }
//            return existingTranscription
//        }
//        
//        // Transcribe the audio file
//        let transcription = try await transcribeAudioFile(currentChapterURL, for: audiobook, chapterIndex: currentChapterIndex)
//        
//        // Cache the transcription
//        await cacheTranscription(transcription, for: audiobook, chapterIndex: currentChapterIndex)
//        
//        return transcription
//    }
//    
//    func stopTranscription() {
//        // Note: WhisperKit doesn't support stopping mid-transcription in the current API
//        // But we can reset our state
//        DispatchQueue.main.async { [weak self] in
//            self?.isTranscribing = false
//            self?.transcriptionProgress = 0
//        }
//    }
//    
//    // MARK: - Helper Methods
//    private func getChapterFiles(from folderURL: URL) -> [String]? {
//        let manifestURL = folderURL.appendingPathComponent("audiobook_manifest.json")
//        
//        guard let manifestData = try? Data(contentsOf: manifestURL),
//              let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
//              let chaptersData = manifest["chapters"] as? [[String: Any]] else {
//            return nil
//        }
//        
//        return chaptersData.compactMap { $0["fileName"] as? String }
//    }
//    
//    // MARK: - Caching (reuse existing Core Data logic)
//    private func getCachedTranscription(for audiobook: Audiobook, chapterIndex: Int) -> String? {
//        let context = persistenceController.context
//        let request: NSFetchRequest<ChapterTranscription> = ChapterTranscription.fetchRequest()
//        request.predicate = NSPredicate(format: "audiobook == %@ AND chapterIndex == %d", audiobook, chapterIndex)
//        
//        do {
//            let transcriptions = try context.fetch(request)
//            return transcriptions.first?.transcriptionText
//        } catch {
//            print("❌ WhisperTranscriptionManager: Error fetching cached transcription: \(error)")
//            return nil
//        }
//    }
//    
//    private func cacheTranscription(_ text: String, for audiobook: Audiobook, chapterIndex: Int) async {
//        let audiobookObjectID = audiobook.objectID
//        await MainActor.run {
//            let context = persistenceController.context
//            guard let audiobook = try? context.existingObject(with: audiobookObjectID) as? Audiobook else {
//                print("❌ WhisperTranscriptionManager: Failed to find audiobook for caching")
//                return
//            }
//            
//            // Remove existing transcription if any
//            let request: NSFetchRequest<ChapterTranscription> = ChapterTranscription.fetchRequest()
//            request.predicate = NSPredicate(format: "audiobook == %@ AND chapterIndex == %d", audiobook, chapterIndex)
//            
//            if let existingTranscription = try? context.fetch(request).first {
//                context.delete(existingTranscription)
//            }
//            
//            // Create new transcription
//            let transcription = ChapterTranscription(context: context)
//            transcription.id = UUID()
//            transcription.audiobook = audiobook
//            transcription.chapterIndex = Int16(chapterIndex)
//            transcription.transcriptionText = text
//            transcription.dateCreated = Date()
//            
//            persistenceController.save()
//            print("💾 WhisperTranscriptionManager: Cached transcription for chapter \(chapterIndex)")
//        }
//    }
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
//    }
//}
//
//// MARK: - Extensions for WhisperKit compatibility
//extension WhisperTranscriptionManager {
//    
//    // Helper to get available models
//    func getAvailableModels() -> [String] {
//        return [
//            "openai_whisper-tiny",      // Fastest, least accurate (~39 MB)
//            "openai_whisper-base",      // Good balance (~74 MB) - recommended
//            "openai_whisper-small",     // Better accuracy (~244 MB)
//            "openai_whisper-medium",    // High accuracy (~769 MB)
//            "openai_whisper-large-v3"  // Best accuracy (~1550 MB)
//        ]
//    }
//    
//    // Switch to a different model if needed
//    func switchModel(to modelName: String) async throws {
//        await MainActor.run {
//            isModelLoading = true
//            modelLoadingProgress = 0
//        }
//        
//        do {
//            whisperKit = try await WhisperKit(
//                model: modelName,
//                download: true,
//                computeUnits: .all,
//                prewarm: true,
//                load: true
//            ) { progress in
//                Task { @MainActor in
//                    self.modelLoadingProgress = progress.fractionCompleted
//                }
//            }
//            
//            await MainActor.run {
//                isModelLoading = false
//                modelLoadingProgress = 1.0
//            }
//            
//        } catch {
//            await MainActor.run {
//                isModelLoading = false
//            }
//            throw WhisperTranscriptionError.modelLoadingFailed
//        }
//    }
//}
