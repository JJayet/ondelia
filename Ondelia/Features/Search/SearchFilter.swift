import Foundation

// MARK: - Facets & Sorts
enum SearchFilter: CaseIterable { case all, inProgress, completed, notStarted
    func includes(_ book: AudiobookModel) -> Bool {
        switch self {
        case .all: true
        case .inProgress: book.currentPosition > 0 && !book.isFinished
        case .completed: book.isFinished
        case .notStarted: book.currentPosition == 0
        }
    }

    var label: String {
        switch self {
        case .all: return NSLocalizedString("All", comment: "Filter: all audiobooks")
        case .inProgress: return NSLocalizedString("In Progress", comment: "Filter: books in progress")
        case .completed: return NSLocalizedString("Completed", comment: "Filter: completed books")
        case .notStarted: return NSLocalizedString("Not Started", comment: "Filter: books not started")
        }
    }
}

enum SearchSort: CaseIterable { case relevance, recent, title, author, progress
    var label: String {
        switch self {
        case .relevance: return NSLocalizedString("Relevance", comment: "Sort by relevance")
        case .recent: return NSLocalizedString("Recently Played", comment: "Sort by recently played")
        case .title: return NSLocalizedString("Title", comment: "Sort by title")
        case .author: return NSLocalizedString("Author", comment: "Sort by author")
        case .progress: return NSLocalizedString("Progress", comment: "Sort by progress")
        }
    }
}
