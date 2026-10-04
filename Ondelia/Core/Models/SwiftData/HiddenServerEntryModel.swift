import Foundation
import SwiftData

/// A server audiobook, server series, server collection or author the listener chose not to see.
///
/// Synced, so hiding on one device hides on all. Two devices hiding the same entry make two
/// records; showing it again deletes every match. CloudKit-compatible: defaults on all.
@Model
final class HiddenServerEntryModel {
    enum Kind: String, CaseIterable {
        case book, series, collection, author
    }

    var serverID: String = ""
    /// A `Kind` raw value: SwiftData with CloudKit stores plain values best.
    var kind: String = ""
    /// The AudiobookShelf id of the book, series, collection or author.
    var entityID: String = ""
    /// Shown in Settings without fetching the server.
    var name: String = ""
    var hiddenAt: Date = Date()

    init(serverID: String, kind: Kind, entityID: String, name: String) {
        self.serverID = serverID
        self.kind = kind.rawValue
        self.entityID = entityID
        self.name = name
    }
}
