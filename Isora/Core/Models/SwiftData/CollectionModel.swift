import Foundation
import SwiftData

/// A named shelf of books. Hardcover series become one automatically (`hardcoverSeriesID` set);
/// the rest are made by hand. A book can sit in any number of them.
///
/// Membership is an ordered list of book ids rather than a relationship: the order is the
/// collection's own (reading order for a series, and later whatever the listener drags it to),
/// and a deleted book simply stops resolving. CloudKit-compatible: defaults on everything.
@Model
final class CollectionModel {
    var id: UUID = UUID()
    var name: String = ""
    var hardcoverSeriesID: Int?
    var bookIDs: [UUID] = []
    var dateCreated: Date = Date()

    init(id: UUID = UUID(), name: String, hardcoverSeriesID: Int? = nil, bookIDs: [UUID] = [], dateCreated: Date = Date()) {
        self.id = id
        self.name = name
        self.hardcoverSeriesID = hardcoverSeriesID
        self.bookIDs = bookIDs
        self.dateCreated = dateCreated
    }

    var isSeries: Bool { hardcoverSeriesID != nil }
}
