import Foundation
import SwiftData

/// Which AudiobookShelf server an item lives on, by the server's `AudiobookShelfAccount.id`.
///
/// Its own entity rather than a column on `AudiobookShelfLinkModel`, for the reason spelled out
/// on `TranscriptWindowModel`. Written beside every link; links made before several servers
/// existed get one at launch, pointing at the first server (`backfillItemServers`). Two devices
/// writing the same pair is harmless: readers take any match. CloudKit-compatible: defaults on all.
@Model
final class AudiobookShelfItemServerModel {
    var itemID: String = ""
    var serverID: String = ""

    init(itemID: String, serverID: String) {
        self.itemID = itemID
        self.serverID = serverID
    }
}
