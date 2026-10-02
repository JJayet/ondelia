import Foundation
import SwiftData

/// Which AudiobookShelf item a library book was downloaded from.
///
/// Its own entity rather than a column on `AudiobookModel`, for the reason spelled out on
/// `TranscriptWindowModel`: the model classes are shared between schema versions, so a new
/// column changes every earlier version's checksum and the store no longer opens. Keyed by the
/// book's id; `AudiobookManager` deletes a book's links with the book. CloudKit-compatible:
/// defaults on all.
@Model
final class AudiobookShelfLinkModel {
    var audiobookID: UUID = UUID()
    var itemID: String = ""

    init(audiobookID: UUID, itemID: String) {
        self.audiobookID = audiobookID
        self.itemID = itemID
    }
}
