import Foundation
import SwiftData

/// A Hardcover read that a Finish closed. The next listen of that audiobook opens a new read
/// rather than moving this one, so each read-through keeps its own progress and dates.
///
/// Its own entity rather than a field on `HardcoverLink`: the link is stored inside
/// `AudiobookModel`, so a new field changes that entity's hash in every earlier schema version
/// and the store no longer opens (see `TranscriptWindowModel`). Keyed by the audiobook's id;
/// `AudiobookManager` deletes these with the audiobook. CloudKit-compatible: defaults on all.
@Model
final class HardcoverClosedReadModel {
    var audiobookID: UUID = UUID()
    var readID: Int = 0

    init(audiobookID: UUID, readID: Int) {
        self.audiobookID = audiobookID
        self.readID = readID
    }
}
