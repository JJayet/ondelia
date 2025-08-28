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
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private let persistenceController = PersistenceController.shared
    
    private init() {
        requestTranscriptionPermission()
    }
    
    deinit {
        stopTranscription()
    }
    
    // MARK: - Permission Handling
    private func requestTranscriptionPermission() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    print("✅ TranscriptionManager: Speech recognition authorized")
                case .denied:
                    print("❌ TranscriptionManager: Speech recognition denied")
                case .restricted:
                    print("⚠️ TranscriptionManager: Speech recognition restricted")
                case .notDetermined:
                    print("⏳ TranscriptionManager: Speech recognition not determined")
                @unknown default:
                    print("❓ TranscriptionManager: Unknown authorization status")
                }
            }
        }
    }
    
    var isAuthorizationGranted: Bool {
        return SFSpeechRecognizer.authorizationStatus() == .authorized
    }
    
    // MARK: - Transcription Methods
    func transcribeAudioFile(_ audioURL: URL, for audiobook: Audiobook, chapterIndex: Int) async throws -> String {
        guard isAuthorizationGranted else {
            throw TranscriptionError.authorizationDenied
        }
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }
        
        print("🎤 TranscriptionManager: Starting transcription for chapter \(chapterIndex)")
        
        let pipe = try await WhisperKit()
        let results = try await pipe.transcribe(audioPath: audioURL.path)
        guard let transcription = results.first?.text else {
            print("❌ TranscriptionManager: No transcription result returned")
            throw TranscriptionError.transcriptionFailed
        }
        print("✅ TranscriptionManager: WhisperKit transcription completed")
        await MainActor.run {
            self.currentTranscription = transcription
            self.transcriptionProgress = 1.0
        }
        return transcription
    }
    
    func transcribeCurrentChapter(for audiobook: Audiobook, currentChapterIndex: Int) async throws -> String {
        // Get the current chapter file URL
        guard let folderURL = audiobook.fileURL.map(URL.init(fileURLWithPath:)),
              let chapterFiles = getChapterFiles(from: folderURL),
              currentChapterIndex < chapterFiles.count else {
            throw TranscriptionError.chapterNotFound
        }
        
        let currentChapterURL = folderURL.appendingPathComponent(chapterFiles[currentChapterIndex])
        
        // Check if transcription already exists
        if let existingTranscription = getCachedTranscription(for: audiobook, chapterIndex: currentChapterIndex) {
            print("📖 TranscriptionManager: Using cached transcription")
            await MainActor.run {
                currentTranscription = existingTranscription
            }
            return existingTranscription
        }
        
        // Transcribe the audio file
        let transcription = try await transcribeAudioFile(currentChapterURL, for: audiobook, chapterIndex: currentChapterIndex)
        
        // Cache the transcription
        await cacheTranscription(transcription, for: audiobook, chapterIndex: currentChapterIndex)
        
        return transcription
    }
    
    func stopTranscription() {
        recognitionTask?.cancel()
        recognitionTask = nil
        
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
        let context = persistenceController.context
        let request: NSFetchRequest<ChapterTranscription> = ChapterTranscription.fetchRequest()
        request.predicate = NSPredicate(format: "audiobook == %@ AND chapterIndex == %d", audiobook, chapterIndex)
        
        do {
            let transcriptions = try context.fetch(request)
            return transcriptions.first?.transcriptionText
        } catch {
            print("❌ TranscriptionManager: Error fetching cached transcription: \(error)")
            return nil
        }
    }
    
    private func cacheTranscription(_ text: String, for audiobook: Audiobook, chapterIndex: Int) async {
        let audiobookObjectID = audiobook.objectID
        await MainActor.run {
            let context = persistenceController.context
            guard let audiobook = try? context.existingObject(with: audiobookObjectID) as? Audiobook else {
                print("❌ TranscriptionManager: Failed to find audiobook for caching")
                return
            }
            
            let transcription = ChapterTranscription(context: context)
            
            transcription.id = UUID()
            transcription.audiobook = audiobook
            transcription.chapterIndex = Int16(chapterIndex)
            transcription.transcriptionText = text
            transcription.dateCreated = Date()
            
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
