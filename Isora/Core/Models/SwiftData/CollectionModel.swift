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
    /// `CollectionSort` raw value. Manual means `bookIDs` order, which the listener can drag.
    var sortRaw: Int = 0

    init(
        id: UUID = UUID(),
        name: String,
        hardcoverSeriesID: Int? = nil,
        bookIDs: [UUID] = [],
        dateCreated: Date = Date(),
        sort: CollectionSort = .manual
    ) {
        self.id = id
        self.name = name
        self.hardcoverSeriesID = hardcoverSeriesID
        self.bookIDs = bookIDs
        self.dateCreated = dateCreated
        self.sortRaw = sort.rawValue
    }

    var isSeries: Bool { hardcoverSeriesID != nil }

    var sort: CollectionSort {
        get { CollectionSort(rawValue: sortRaw) ?? .manual }
        set { sortRaw = newValue.rawValue }
    }
}

/// How a collection orders its books. Stored as an Int so adding a case never touches the store.
enum CollectionSort: Int, CaseIterable {
    case manual = 0
    case seriesPosition = 1
    case title = 2
    case author = 3
    case dateAdded = 4
    case releaseDate = 5

    var displayName: String {
        switch self {
        case .manual: return NSLocalizedString("Manual", comment: "Collection order: as arranged by hand")
        case .seriesPosition: return NSLocalizedString("Series order", comment: "Collection order: Hardcover volume position")
        case .title: return NSLocalizedString("Title", comment: "Sort by title")
        case .author: return NSLocalizedString("Author", comment: "Sort by author")
        case .dateAdded: return NSLocalizedString("Date Added", comment: "Sort by date added")
        case .releaseDate: return NSLocalizedString("Publication date", comment: "Collection order: Hardcover release date")
        }
    }
}
