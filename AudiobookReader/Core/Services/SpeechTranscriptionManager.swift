import Foundation
import Speech
import AVFoundation
import CoreMedia

/// On-device transcription through `SpeechAnalyzer` (iOS 26).
///
/// Replaces WhisperKit: the system ships the recognition models, so there is no model picker,
/// no bundled weights and no download plumbing of our own — only a per-language asset that
/// `AssetInventory` installs on demand and shares with every other app on the device.
@MainActor
@Observable
final class SpeechTranscriptionManager {
    static let shared = SpeechTranscriptionManager()

    var isTranscribing = false
    var currentTranscription = ""
    var transcriptionProgress: Double = 0
    /// True while the system downloads the language asset for the selected locale.
    var isModelLoading = false
    var modelLoadingProgress: Double = 0

    private let themeManager = ThemeManager.shared

    private init() {}

    /// The engine itself needs no warm-up; only a missing language asset can hold a run back.
    var isReady: Bool { SpeechTranscriber.isAvailable && !isModelLoading }

    // MARK: - Locales and assets

    /// The locale the system will actually recognise for the language chosen in Settings.
    /// Returns nil when the device supports no variant of it.
    func resolvedLocale() async -> Locale? {
        let requested = Locale(identifier: themeManager.transcriptionLanguage.rawValue)
        return await SpeechTranscriber.supportedLocale(equivalentTo: requested)
    }

    /// Whether the selected language is unsupported, installable, downloading, or ready.
    func assetStatus() async -> AssetInventory.Status {
        guard let locale = await resolvedLocale() else { return .unsupported }
        return await AssetInventory.status(forModules: [Self.makeTranscriber(locale: locale)])
    }

    /// Downloads the language asset if it is not installed yet. Safe to call repeatedly:
    /// `assetInstallationRequest` returns nil once nothing is left to fetch.
    func installAssetsIfNeeded() async throws {
        guard let locale = await resolvedLocale() else {
            throw TranscriptionError.recognizerUnavailable
        }
        try await installAssets(for: Self.makeTranscriber(locale: locale))
    }

    private func installAssets(for transcriber: SpeechTranscriber) async throws {
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            return
        }
        isModelLoading = true
        modelLoadingProgress = 0
        defer {
            isModelLoading = false
            modelLoadingProgress = 1
        }
        // Progress is observed rather than polled so the settings row can show a real bar.
        let progress = request.progress
        let observer = Task { @MainActor [weak self] in
            while !Task.isCancelled && !progress.isFinished {
                self?.modelLoadingProgress = progress.fractionCompleted
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        defer { observer.cancel() }
        try await request.downloadAndInstall()
    }

    // MARK: - Transcription

    func transcribeAudioFile(
        _ audioURL: URL,
        for audiobook: AudiobookModel,
        chapterIndex: Int
    ) async throws -> TranscriptionResult {
        guard SpeechTranscriber.isAvailable, let locale = await resolvedLocale() else {
            throw TranscriptionError.recognizerUnavailable
        }

        let transcriber = Self.makeTranscriber(locale: locale)
        try await installAssets(for: transcriber)

        Log.transcription.debug("🎤 SpeechTranscriptionManager: Starting transcription for chapter \(chapterIndex)")

        isTranscribing = true
        transcriptionProgress = 0
        defer {
            isTranscribing = false
            transcriptionProgress = 0
        }

        let hasAccess = audioURL.startAccessingSecurityScopedResource()
        defer { if hasAccess { audioURL.stopAccessingSecurityScopedResource() } }

        do {
            let file = try AVAudioFile(forReading: audioURL)
            let totalSeconds = Double(file.length) / file.fileFormat.sampleRate

            // Results must be consumed while analysis runs, so start collecting first.
            let collector = Task { [weak self] in
                var text = ""
                var timings: [(text: String, start: Double, end: Double)] = []
                for try await result in transcriber.results {
                    let attributed = result.text
                    text += String(attributed.characters)
                    timings.append(contentsOf: Self.timings(in: attributed))
                    let reached = result.range.end.seconds
                    if totalSeconds > 0, reached.isFinite {
                        self?.report(progress: min(reached / totalSeconds, 1), text: text)
                    }
                }
                return (text, timings)
            }

            let analyzer = try await SpeechAnalyzer(inputAudioFile: file, modules: [transcriber])
            try await analyzer.finalizeAndFinishThroughEndOfInput()

            let (text, timings) = try await collector.value
            let segments = Self.makeSegments(timings)

            currentTranscription = text
            transcriptionProgress = 1
            Log.transcription.debug("✅ SpeechTranscriptionManager: Transcription completed")

            return TranscriptionResult(
                text: text,
                segments: segments,
                language: locale.identifier
            )
        } catch {
            Log.transcription.error("❌ SpeechTranscriptionManager: Transcription error: \(error)")
            throw SpeechTranscriptionError.transcriptionFailed(error)
        }
    }

    private func report(progress: Double, text: String) {
        transcriptionProgress = progress
        currentTranscription = text
    }

    private static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        // `.audioTimeRange` is what makes the transcript scrubbable: without it the result
        // carries text but no per-word timing to line up against playback.
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )
    }

    /// Pulls one timing per attributed run. A run is roughly a word, which is finer than
    /// Whisper's phrase segments and lines up better with playback.
    static func timings(in attributed: AttributedString) -> [(text: String, start: Double, end: Double)] {
        attributed.runs.compactMap { run in
            guard let range = run.audioTimeRange else { return nil }
            let text = String(attributed[run.range].characters)
            guard !text.isEmpty else { return nil }
            return (text: text, start: range.start.seconds, end: range.end.seconds)
        }
    }

    /// Drops segments the recogniser could not place on the timeline, so the transcript view
    /// never tries to seek to a NaN or run a range backwards.
    static func makeSegments(_ segments: [(text: String, start: Double, end: Double)]) -> [TranscriptionSegment] {
        segments.compactMap { segment in
            guard segment.start.isFinite,
                  segment.end.isFinite,
                  segment.start >= 0,
                  segment.end >= segment.start else { return nil }
            return TranscriptionSegment(text: segment.text, start: segment.start, end: segment.end)
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
enum SpeechTranscriptionError: Error, LocalizedError {
    case chapterNotFound
    case transcriptionFailed(Error)
    case assetInstallationFailed

    var errorDescription: String? {
        switch self {
        case .chapterNotFound:
            return NSLocalizedString("Chapter file not found", comment: "Transcription error")
        case .transcriptionFailed(let error):
            return String(
                format: NSLocalizedString("Transcription failed: %@", comment: "Transcription error"),
                error.localizedDescription
            )
        case .assetInstallationFailed:
            return NSLocalizedString(
                "The language model could not be downloaded",
                comment: "Transcription error"
            )
        }
    }
}
