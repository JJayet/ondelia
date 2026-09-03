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

        var descriptor: SortDescriptor<AudiobookModel> {
            switch self {
            case .title:
                return SortDescriptor(\AudiobookModel.title)
            case .author:
                return SortDescriptor(\AudiobookModel.author)
            case .lastPlayed:
                return SortDescriptor(\AudiobookModel.lastPlayed, order:.reverse)
            case .dateAdded:
                return SortDescriptor(\AudiobookModel.dateAdded, order:.reverse)
            case .progress:
                return SortDescriptor(\AudiobookModel.currentPosition, order:.reverse)
            }
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
