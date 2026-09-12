import Foundation
import SwiftData

/// The transcript of one window of one track: text plus the per-word timing blob.
///
/// Keyed by the book's id, the track index and the window's track-local bounds. No
/// relationship to the book: adding a column to an existing model would change every earlier
/// schema version's checksum, since the model classes are shared between versions. A new
/// entity, like the listening log before it, leaves them untouched. `AudiobookManager`
/// deletes a book's windows with the book. CloudKit-compatible: defaults on all.
@Model
final class TranscriptWindowModel {
    var id: UUID = UUID()
    var audiobookID: UUID = UUID()
    var trackIndex: Int16 = 0
    /// Track-local seconds.
    var windowStart: Double = 0
    var windowEnd: Double = 0
    var text: String = ""
    var language: String?
    var engine: String?
    var segmentsData: Data?
    var dateCreated: Date = Date()

    init(
        audiobookID: UUID,
        trackIndex: Int16,
        windowStart: Double,
        windowEnd: Double,
        text: String,
        language: String?,
        engine: String?,
        segmentsData: Data?
    ) {
        self.audiobookID = audiobookID
        self.trackIndex = trackIndex
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.text = text
        self.language = language
        self.engine = engine
        self.segmentsData = segmentsData
    }
}
