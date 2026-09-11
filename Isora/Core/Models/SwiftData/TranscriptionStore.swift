import Foundation
import SwiftData

/// Reads and writes cached transcripts on their own SwiftData context.
///
/// Transcripts are the largest rows the app stores — a window of prose plus a per-word timing
/// blob — and the rest of SwiftData here runs on the main context. `@ModelActor` gives this one
/// its own context and its own executor, so a transcript can be fetched or saved without the
/// main actor decoding it.
///
/// Nothing here hands a `@Model` object out: the boundary is `TranscriptionResult`, a value
/// type, and the audiobook is addressed by its `UUID`. That is what makes the actor safe to
/// cross under Swift 6, and it means no SwiftData object is ever touched off its own context.
@ModelActor
actor TranscriptionStore {
    /// The cached transcript for a window in a language, or nil when it has not been transcribed.
    func cachedResult(for request: TranscriptionRequest, language: String) -> TranscriptionResult? {
        guard let cached = try? fetchRow(for: request, language: language) else { return nil }

        var segments: [TranscriptionSegment] = []
        if let data = cached.segmentsData,
           let decoded = try? JSONDecoder().decode([TranscriptionSegment].self, from: data) {
            segments = decoded
        }

        return TranscriptionResult(
            text: cached.text,
            segments: segments,
            language: cached.language ?? "en"
        )
    }

    /// Replaces whatever was cached for this window in the result's language.
    func save(_ result: TranscriptionResult, for request: TranscriptionRequest, engine: String) {
        // One transcript per window and language, so an earlier attempt is dropped rather
        // than duplicated.
        if let existing = try? fetchRow(for: request, language: result.language) {
            modelContext.delete(existing)
        }
        sweepLegacyRows(for: request)

        // No relationship to check against, so a book that is gone is caught here rather than
        // leaving a transcript nobody can reach.
        let audiobookID = request.audiobookID
        var descriptor = FetchDescriptor<AudiobookModel>(
            predicate: #Predicate { $0.id == audiobookID }
        )
        descriptor.fetchLimit = 1
        guard ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0 else {
            Log.transcription.error("❌ TranscriptionStore: No audiobook to attach the transcript to")
            return
        }

        let row = TranscriptWindowModel(
            audiobookID: audiobookID,
            trackIndex: Int16(request.trackIndex),
            windowStart: request.start,
            windowEnd: request.end,
            text: result.text,
            language: result.language,
            engine: engine,
            segmentsData: result.segments.isEmpty ? nil : try? JSONEncoder().encode(result.segments)
        )
        modelContext.insert(row)
        do {
            try modelContext.save()
            Log.transcription.debug("💾 TranscriptionStore: Cached track \(request.trackIndex) \(request.start)-\(request.end)s")
        } catch {
            Log.transcription.error("❌ TranscriptionStore: Could not save the transcript: \(error)")
        }
    }

    private func fetchRow(for request: TranscriptionRequest, language: String) throws -> TranscriptWindowModel? {
        let audiobookID = request.audiobookID
        let trackIndex = Int16(request.trackIndex)
        let start = request.start
        let end = request.end
        var descriptor = FetchDescriptor<TranscriptWindowModel>(
            predicate: #Predicate { row in
                row.audiobookID == audiobookID
                    && row.trackIndex == trackIndex
                    && row.windowStart == start
                    && row.windowEnd == end
                    && row.language == language
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Rows written before windows existed cover a whole track and are never read again, so
    /// the first new transcript of that track drops them.
    private func sweepLegacyRows(for request: TranscriptionRequest) {
        let audiobookID = request.audiobookID
        let trackIndex = Int16(request.trackIndex)
        let descriptor = FetchDescriptor<ChapterTranscriptionModel>(
            predicate: #Predicate { row in
                row.chapterIndex == trackIndex && row.audiobook?.id == audiobookID
            }
        )
        for legacy in (try? modelContext.fetch(descriptor)) ?? [] {
            modelContext.delete(legacy)
        }
    }
}
