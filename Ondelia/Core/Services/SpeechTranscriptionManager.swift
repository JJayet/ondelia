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
    var isDownloadingModel = false
    /// Share of the window in flight that has been recognised, 0 to 1.
    var transcriptionProgress: Double = 0
    /// What has been recognised so far of the request in flight, so the view can show the text
    /// before the window finishes. Nil between jobs and for cache hits.
    private(set) var live: LiveTranscript?
    /// The language the last request was, or is being, recognised in.
    private(set) var resolvedLocale: Locale?

    struct LiveTranscript {
        let request: TranscriptionRequest
        var text = ""
        var segments: [TranscriptionSegment] = []
    }

    private let swiftDataController = SwiftDataController.shared
    private var transcriptionStore: TranscriptionStore?
    /// The one analysis running. Owned here rather than by the view: a view task that was
    /// cancelled could still be unwinding while its replacement started, and its exit reset
    /// state that by then belonged to the new job.
    private var current: Task<TranscriptionResult, Error>?

    private init() {}

    // MARK: - Locales

    /// Resolves the default independently of any saved override or active transcription job.
    static func defaultLocale(for url: URL) async -> Locale? {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        return await resolvedLocale(for: url, preferred: nil)
    }

    /// The locale to recognise a file in: the reader's choice for the book, else the language
    /// the file itself declares, else the device language. Nil when none is supported.
    private static func resolvedLocale(for url: URL, preferred: String?) async -> Locale? {
        let chosen = preferred.map { Locale(identifier: $0) }
        for candidate in [chosen, await declaredLocale(for: url), Locale.current].compactMap({ $0 }) {
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

    /// Downloads the language asset when the device does not have it yet.
    private func installAssets(for transcriber: SpeechTranscriber) async throws {
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            return
        }
        isDownloadingModel = true
        defer { isDownloadingModel = false }
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

    /// The transcript of one window, from the cache when it has one. Cancelling the caller
    /// cancels the analysis; starting another request cancels the one in flight.
    /// - Parameter bypassCache: re-transcribes and overwrites the cached row.
    func transcribe(_ request: TranscriptionRequest, bypassCache: Bool = false) async throws -> TranscriptionResult {
        current?.cancel()
        // Let the old job finish unwinding, so its `defer`s cannot clear this job's state.
        _ = try? await current?.value

        let job = Task { try await run(request, bypassCache: bypassCache) }
        current = job
        defer { if current == job { current = nil } }
        return try await withTaskCancellationHandler {
            try await job.value
        } onCancel: {
            job.cancel()
        }
    }

    func cancel() {
        current?.cancel()
    }

    private func run(_ request: TranscriptionRequest, bypassCache: Bool) async throws -> TranscriptionResult {
        isTranscribing = true
        // Every exit, thrown ones included: a throw used to leave the loader up for good, with
        // refresh disabled behind it.
        defer {
            isTranscribing = false
            transcriptionProgress = 0
        }

        let audioURL = request.url
        // Access first: reading the file's language tag opens it just like the analyzer does.
        let hasAccess = audioURL.startAccessingSecurityScopedResource()
        defer { if hasAccess { audioURL.stopAccessingSecurityScopedResource() } }

        // The language is part of the cache key, so it is settled before the cache is read:
        // a transcript in one language must never answer for another.
        guard SpeechTranscriber.isAvailable,
              let locale = await Self.resolvedLocale(for: audioURL, preferred: request.language) else {
            throw TranscriptionError.recognizerUnavailable
        }
        resolvedLocale = locale
        Log.transcription.debug("🌍 SpeechTranscriptionManager: Recognising in \(locale.identifier)")

        if !bypassCache, let cached = await store()?.cachedResult(for: request, language: locale.identifier) {
            Log.transcription.debug("📖 SpeechTranscriptionManager: Using cached transcription")
            return cached
        }

        let result = try await transcribeWindow(request, locale: locale)
        await store()?.save(result, for: request, engine: "SpeechAnalyzer")
        return result
    }

    private func transcribeWindow(_ request: TranscriptionRequest, locale: Locale) async throws -> TranscriptionResult {
        let audioURL = request.url
        let transcriber = Self.makeTranscriber(locale: locale)
        try await installAssets(for: transcriber)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionError.recognizerUnavailable
        }

        Log.transcription.debug("🎤 SpeechTranscriptionManager: Transcribing track \(request.trackIndex) \(request.start)-\(request.end)s")

        transcriptionProgress = 0
        live = LiveTranscript(request: request)
        defer { live = nil }
        let windowLength = max(request.end - request.start, 1)

        do {
            // Results must be consumed while analysis runs, so start collecting first.
            let collector = Task { [weak self] in
                var text = ""
                var segments: [TranscriptionSegment] = []
                for try await result in transcriber.results {
                    let attributed = result.text
                    text += String(attributed.characters)
                    segments += Self.makeSegments(Self.timings(in: attributed))
                    let reached = result.range.end.seconds
                    if reached.isFinite {
                        self?.transcriptionProgress = min(max((reached - request.start) / windowLength, 0), 1)
                    }
                    self?.live = LiveTranscript(request: request, text: text, segments: segments)
                }
                return (text, segments)
            }
            // The collector awaits `transcriber.results` until the analyzer finishes. If setup
            // or finalisation throws below, nothing else ends that stream, so cancel it on every
            // exit; after a normal completion the task is already done and this is a no-op.
            defer { collector.cancel() }

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let input = AudioWindowSequence(url: audioURL, start: request.start, end: request.end, format: format)
            // Closing the view cancels the task; without this the analyzer would run the whole
            // window to its end before the cancellation is noticed.
            try await withTaskCancellationHandler {
                try await analyzer.start(inputSequence: input)
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } onCancel: {
                Task { await analyzer.cancelAndFinishNow() }
            }

            let (text, segments) = try await collector.value
            try Task.checkCancellation()

            transcriptionProgress = 1
            Log.transcription.debug("✅ SpeechTranscriptionManager: Transcription completed")

            return TranscriptionResult(
                text: text,
                segments: segments,
                language: locale.identifier
            )
        } catch is CancellationError {
            throw CancellationError()
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
    case audioUnreadable
    case transcriptionFailed(Error)
    case assetInstallationFailed

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return NSLocalizedString("Speech recognizer unavailable", comment: "Transcription error")
        case .chapterNotFound, .audioUnreadable:
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
