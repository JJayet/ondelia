import Foundation
import WhisperKit
import AVFoundation

@MainActor
class WhisperTranscriptionManager: ObservableObject {
    static let shared = WhisperTranscriptionManager()
    
    @Published var isTranscribing = false
    @Published var currentTranscription = ""
    @Published var transcriptionProgress: Double = 0
    @Published var isModelLoading = false
    @Published var modelLoadingProgress: Double = 0
    
    private var whisperKit: WhisperKit?
    private let themeManager = ThemeManager.shared
    
    // Current model name tracking
    private var currentModelName: String = ""
    
    private init() {
        // Lazy init: do not download automatically. Initialization happens on demand via switchModel or when first used.
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
    
    func transcribeAudioFile(_ audioURL: URL, for audiobook: AudiobookModel, chapterIndex: Int) async throws -> TranscriptionResult {
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
            // Start transcription using simplified API
            let result = try await whisperKit.transcribe(audioPath: audioURL.path)
            
            await MainActor.run {
                transcriptionProgress = 0.8
            }
            
            await MainActor.run {
                transcriptionProgress = 1.0
            }
            
            let whisperResult = result.first
            let finalTranscription = whisperResult?.text ?? ""
            let segments = Self.makeSegments(
                whisperResult?.segments.map { ($0.text, $0.start, $0.end) } ?? []
            )
            
            await MainActor.run {
                currentTranscription = finalTranscription
            }
            
            print("✅ WhisperTranscriptionManager: Transcription completed")
            
            // Create transcription result with timestamps
            return TranscriptionResult(
                text: finalTranscription,
                segments: segments,
                language: whisperResult?.language ?? themeManager.transcriptionLanguage.rawValue
            )
            
        } catch {
            print("❌ WhisperTranscriptionManager: Transcription error: \(error)")
            throw WhisperTranscriptionError.transcriptionFailed(error)
        }
    }

    static func makeSegments(_ segments: [(text: String, start: Float, end: Float)]) -> [TranscriptionSegment] {
        segments.compactMap { segment in
            guard segment.start.isFinite,
                  segment.end.isFinite,
                  segment.start >= 0,
                  segment.end >= segment.start else { return nil }
            return TranscriptionSegment(
                text: segment.text,
                start: Double(segment.start),
                end: Double(segment.end)
            )
        }
    }
    
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
    
}

// MARK: - Data Structures
struct TranscriptionResult {
    let text: String
    let segments: [TranscriptionSegment]
    let language: String
}

struct TranscriptionSegment: Codable, Equatable {
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
