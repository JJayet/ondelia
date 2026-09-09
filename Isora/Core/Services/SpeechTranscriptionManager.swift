import Foundation
import Speech
import AVFoundation
import CoreMedia
import SwiftData

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
    var transcriptionProgress: Double = 0

    private let swiftDataController = SwiftDataController.shared
    private var transcriptionStore: TranscriptionStore?

    private init() {}

    // MARK: - Locales

    /// The locale to recognise a file in: the language the file itself declares, else the
    /// device language. Nil when the device supports neither.
    private static func resolvedLocale(for url: URL) async -> Locale? {
        for candidate in [await declaredLocale(for: url), Locale.current].compactMap({ $0 }) {
            if let supported = await SpeechTranscriber.supportedLocale(equivalentTo: candidate) {
                return supported
            }
        }
        return nil
    }

    /// The language tag carried by the audio track, as ISO 639-2 ("fra"). Missing or "und" on
    /// plenty of files, which is why `resolvedLocale` keeps a fallback.
    private static func declaredLocale(for url: URL) async -> Locale? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let code = try? await track.load(.languageCode),
              code != "und",
              let alpha2 = Locale.Language(identifier: code).languageCode?.identifier(.alpha2)
        else { return nil }
        return Locale(identifier: alpha2)
    }

    /// Downloads the language asset when the device does not have it yet. The transcription
    /// loader stays up meanwhile, so the download needs no progress of its own.
    private func installAssets(for transcriber: SpeechTranscriber) async throws {
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            return
        }
        try await request.downloadAndInstall()
    }

    // MARK: - Transcription

    /// Built on first use: reading `container` before the store has loaded would trap.
    private func store() -> TranscriptionStore? {
        guard swiftDataController.isLoaded else { return nil }
        if let transcriptionStore { return transcriptionStore }
        let store = TranscriptionStore(modelContainer: swiftDataController.container)
        transcriptionStore = store
        return store
    }

    /// The transcript for the chapter being heard, as spoken. Translation is the caller's job:
    /// caching a translation under a row that claims to hold the original made "Original" show
    /// translated text and pinned the result to whatever language was selected at the time.
    /// - Parameter bypassCache: re-transcribes and overwrites the cached row.
    func transcribeCurrentChapter(
        for audiobook: AudiobookModel,
        chapterIndex: Int,
        bypassCache: Bool = false
    ) async throws -> TranscriptionResult {
        isTranscribing = true
        // Every exit, thrown ones included: a throw used to leave the loader up for good, with
        // refresh disabled behind it.
        defer { isTranscribing = false }

        // The same timeline the player uses, so the index here means the file being heard —
        // and a single-file book, which has no manifest to read, resolves to its one track.
        guard let url = audiobook.resolvedFileURL else {
            throw TranscriptionError.chapterNotFound
        }
        let tracks = await AudiobookPlayer.makeTracks(at: url, fallbackDuration: audiobook.duration)
        guard tracks.indices.contains(chapterIndex) else {
            throw TranscriptionError.chapterNotFound
        }

        let audiobookID = audiobook.id
        let chapter = Int16(chapterIndex)

        if !bypassCache,
           let cached = await store()?.cachedResult(audiobookID: audiobookID, chapterIndex: chapter) {
            Log.transcription.debug("📖 SpeechTranscriptionManager: Using cached transcription")
            return cached
        }

        let result = try await transcribeAudioFile(
            tracks[chapterIndex].url,
            for: audiobook,
            chapterIndex: chapterIndex
        )
        await store()?.save(result, audiobookID: audiobookID, chapterIndex: chapter, engine: "SpeechAnalyzer")
        return result
    }

    private func transcribeAudioFile(
        _ audioURL: URL,
        for audiobook: AudiobookModel,
        chapterIndex: Int
    ) async throws -> TranscriptionResult {
        // Access first: reading the file's language tag opens it just like the analyzer does.
        let hasAccess = audioURL.startAccessingSecurityScopedResource()
        defer { if hasAccess { audioURL.stopAccessingSecurityScopedResource() } }

        guard SpeechTranscriber.isAvailable, let locale = await Self.resolvedLocale(for: audioURL) else {
            throw TranscriptionError.recognizerUnavailable
        }
        Log.transcription.debug("🌍 SpeechTranscriptionManager: Recognising in \(locale.identifier)")

        let transcriber = Self.makeTranscriber(locale: locale)
        try await installAssets(for: transcriber)

        Log.transcription.debug("🎤 SpeechTranscriptionManager: Starting transcription for chapter \(chapterIndex)")

        transcriptionProgress = 0
        defer { transcriptionProgress = 0 }

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
                        self?.transcriptionProgress = min(reached / totalSeconds, 1)
                    }
                }
                return (text, timings)
            }
            // The collector awaits `transcriber.results` until the analyzer finishes. If setup
            // or finalisation throws below, nothing else ends that stream, so cancel it on every
            // exit; after a normal completion the task is already done and this is a no-op.
            defer { collector.cancel() }

            let analyzer = try await SpeechAnalyzer(inputAudioFile: file, modules: [transcriber])
            // Closing the view cancels the task; without this the analyzer would run the whole
            // file to its end before the cancellation is noticed.
            try await withTaskCancellationHandler {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } onCancel: {
                Task { await analyzer.cancelAndFinishNow() }
            }

            let (text, timings) = try await collector.value
            let segments = Self.makeSegments(timings)

            transcriptionProgress = 1
            Log.transcription.debug("✅ SpeechTranscriptionManager: Transcription completed")

            return TranscriptionResult(
                text: text,
                segments: segments,
                language: locale.identifier
            )
        } catch {
            Log.transcription.error("❌ SpeechTranscriptionManager: Transcription error: \(error)")
            throw TranscriptionError.transcriptionFailed(error)
        }
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
struct TranscriptionResult: Sendable {
    let text: String
    let segments: [TranscriptionSegment]
    let language: String
}

struct TranscriptionSegment: Codable, Equatable, Sendable {
    let text: String
    let start: Double
    let end: Double
}

// MARK: - Error Types
enum TranscriptionError: Error, LocalizedError {
    case chapterNotFound
    case recognizerUnavailable
    case transcriptionFailed(Error)
    case assetInstallationFailed

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return NSLocalizedString("Speech recognizer unavailable", comment: "Transcription error")
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

