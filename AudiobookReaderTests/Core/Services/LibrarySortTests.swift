import Foundation
import Testing
@testable import AudiobookReader

@MainActor
struct LibrarySortTests {
    private func books(_ titles: [String], secondsApart: TimeInterval = 1) -> [AudiobookModel] {
        let start = Date(timeIntervalSince1970: 1_000_000)
        return titles.enumerated().map { index, title in
            AudiobookModel(title: title, dateAdded: start.addingTimeInterval(Double(index) * secondsApart))
        }
    }

    private func sorted(_ books: [AudiobookModel], by option: LibraryView.SortOption) -> [String] {
        books.sorted { option.isOrderedBefore($0, $1) }.map { $0.title ?? "" }
    }

    @Test("Titles sort the way Finder sorts them")
    func titlesSortNaturally() {
        let library = books(["Chapter 10", "Chapter 2", "Chapter 1"])

        #expect(sorted(library, by: .title) == ["Chapter 1", "Chapter 2", "Chapter 10"])
    }

    @Test("Never-played books keep the order they were imported in")
    func unplayedBooksKeepImportOrder() {
        // Every lastPlayed is distantPast here, which is what a fresh multi-file import looks like.
        // Titles come from file metadata and say nothing about order, so only dateAdded can.
        let library = books(["Chapter 12", "Epigraph (IV)", "Chapter 4"])

        #expect(sorted(library, by: .lastPlayed) == ["Chapter 12", "Epigraph (IV)", "Chapter 4"])
    }

    @Test("Progress compares how far through, not how many seconds in")
    func progressComparesFractions() {
        let long = AudiobookModel(title: "Long", duration: 72_000, currentPosition: 2_160)   // 3%
        let short = AudiobookModel(title: "Short", duration: 2_400, currentPosition: 2_280)  // 95%
        let unknown = AudiobookModel(title: "Unknown", duration: 0, currentPosition: 500)

        #expect(sorted([long, short, unknown], by: .progress) == ["Short", "Long", "Unknown"])
        #expect(unknown.progressFraction == 0)
    }
}
