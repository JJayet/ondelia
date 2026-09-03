import SwiftUI

extension LibraryView {
    enum ViewMode: String, CaseIterable {
        case list = "list"
        case grid = "grid"

        var displayName: String {
            switch self {
            case .list: return NSLocalizedString("List", comment: "List view mode")
            case .grid: return NSLocalizedString("Grid", comment: "Grid view mode")
            }
        }

        var icon: String {
            switch self {
            case .list: return "list.bullet"
            case .grid: return "square.grid.2x2"
            }
        }
    }

    enum SortOption: String, CaseIterable {
        case title = "title"
        case author = "author"
        case lastPlayed = "lastPlayed"
        case dateAdded = "dateAdded"
        case progress = "progress"

        var displayName: String {
            switch self {
            case .title: return NSLocalizedString("Title", comment: "Sort by title")
            case .author: return NSLocalizedString("Author", comment: "Sort by author")
            case .lastPlayed: return NSLocalizedString("Recently Played", comment: "Sort by recently played")
            case .dateAdded: return NSLocalizedString("Date Added", comment: "Sort by date added")
            case .progress: return NSLocalizedString("Progress", comment: "Sort by progress")
            }
        }

        /// Titles and authors compare the way Finder and the Files app compare them, so
        /// "Chapter 10" lands after "Chapter 2" instead of before it.
        func isOrderedBefore(_ lhs: AudiobookModel, _ rhs: AudiobookModel) -> Bool {
            switch self {
            case .title:
                return Self.byTitle(lhs, rhs)
            case .author:
                let names = (lhs.author ?? "").localizedStandardCompare(rhs.author ?? "")
                return names == .orderedSame ? Self.byTitle(lhs, rhs) : names == .orderedAscending
            case .lastPlayed:
                guard lhs.lastPlayed == rhs.lastPlayed else { return lhs.lastPlayed > rhs.lastPlayed }
                return Self.byImportOrder(lhs, rhs)
            case .dateAdded:
                guard lhs.dateAdded != rhs.dateAdded else { return Self.byTitle(lhs, rhs) }
                return lhs.dateAdded > rhs.dateAdded
            case .progress:
                // How far through, not how many seconds in.
                guard lhs.progressFraction == rhs.progressFraction else {
                    return lhs.progressFraction > rhs.progressFraction
                }
                return Self.byImportOrder(lhs, rhs)
            }
        }

        /// Ties are broken by import order, not left to `sorted`, which is not stable. A library of
        /// books that were never played has every `lastPlayed` equal, and without this the file
        /// order the import took such care to preserve comes out shuffled.
        private static func byImportOrder(_ lhs: AudiobookModel, _ rhs: AudiobookModel) -> Bool {
            guard lhs.dateAdded == rhs.dateAdded else { return lhs.dateAdded < rhs.dateAdded }
            return byTitle(lhs, rhs)
        }

        private static func byTitle(_ lhs: AudiobookModel, _ rhs: AudiobookModel) -> Bool {
            let titles = (lhs.title ?? "").localizedStandardCompare(rhs.title ?? "")
            return titles == .orderedSame
                ? lhs.id.uuidString < rhs.id.uuidString
                : titles == .orderedAscending
        }
    }

    enum FilterOption: String, CaseIterable {
        case all = "all"
        case inProgress = "inProgress"
        case completed = "completed"
        case notStarted = "notStarted"

        var displayName: String {
            switch self {
            case .all: return NSLocalizedString("All", comment: "Filter: all audiobooks")
            case .inProgress: return NSLocalizedString("In Progress", comment: "Filter: books in progress")
            case .completed: return NSLocalizedString("Completed", comment: "Filter: completed books")
            case .notStarted: return NSLocalizedString("Not Started", comment: "Filter: books not started")
            }
        }

        func predicate() -> NSPredicate? {
            switch self {
            case .all:
                return nil
            case .inProgress:
                return NSPredicate(format: "currentPosition > 0 AND isFinished == NO")
            case .completed:
                return NSPredicate(format: "isFinished == YES")
            case .notStarted:
                return NSPredicate(format: "currentPosition == 0")
            }
        }
    }
}
