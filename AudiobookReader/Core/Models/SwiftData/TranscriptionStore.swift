import Foundation
import SwiftData

/// Reads and writes cached chapter transcripts on their own SwiftData context.
///
/// Transcripts are the largest rows the app stores — a chapter of prose plus a per-word timing
/// blob — and the rest of SwiftData here runs on the main context. `@ModelActor` gives this one
/// its own context and its own executor, so a transcript can be fetched or saved without the
/// main actor decoding it.
///
/// Nothing here hands a `@Model` object out: the boundary is `TranscriptionResult`, a value
/// type, and the audiobook is addressed by its `UUID`. That is what makes the actor safe to
/// cross under Swift 6, and it means no SwiftData object is ever touched off its own context.
@ModelActor
actor TranscriptionStore {
    /// The cached transcript for a chapter, or nil when it has not been transcribed.
    func cachedResult(audiobookID: UUID, chapterIndex: Int16) -> TranscriptionResult? {
        guard let cached = try? fetchRow(audiobookID: audiobookID, chapterIndex: chapterIndex),
              let text = cached.transcriptionText else {
            return nil
        }

        var segments: [TranscriptionSegment] = []
        if let data = cached.segmentsData,
           let decoded = try? JSONDecoder().decode([TranscriptionSegment].self, from: data) {
            segments = decoded
        }

        return TranscriptionResult(
            text: text,
            segments: segments,
            language: cached.language ?? "en"
        )
    }

    /// Replaces whatever was cached for this chapter.
    func save(
        _ result: TranscriptionResult,
        audiobookID: UUID,
        chapterIndex: Int16,
        engine: String
    ) {
        // One transcript per chapter, so an earlier attempt is dropped rather than duplicated.
        if let existing = try? fetchRow(audiobookID: audiobookID, chapterIndex: chapterIndex) {
            modelContext.delete(existing)
        }

        var descriptor = FetchDescriptor<AudiobookModel>(
            predicate: #Predicate { $0.id == audiobookID }
        )
        descriptor.fetchLimit = 1
        guard let audiobook = try? modelContext.fetch(descriptor).first else {
            Log.transcription.error("❌ TranscriptionStore: No audiobook to attach the transcript to")
            return
        }

        let row = ChapterTranscriptionModel(
            chapterIndex: chapterIndex,
            transcriptionText: result.text,
            language: result.language,
            transcriptionEngine: engine,
            dateCreated: Date()
        )
        row.audiobook = audiobook
        if !result.segments.isEmpty {
            row.segmentsData = try? JSONEncoder().encode(result.segments)
        }

        modelContext.insert(row)
        do {
            try modelContext.save()
            Log.transcription.debug("💾 TranscriptionStore: Cached chapter \(chapterIndex)")
        } catch {
            Log.transcription.error("❌ TranscriptionStore: Could not save the transcript: \(error)")
        }
    }

    private func fetchRow(audiobookID: UUID, chapterIndex: Int16) throws -> ChapterTranscriptionModel? {
        var descriptor = FetchDescriptor<ChapterTranscriptionModel>(
            predicate: #Predicate { row in
                row.chapterIndex == chapterIndex && row.audiobook?.id == audiobookID
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
