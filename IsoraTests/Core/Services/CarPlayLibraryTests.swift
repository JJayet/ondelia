import Testing
import Foundation
@testable import Isora

@MainActor
struct CarPlayLibraryTests {
    @Test("Continue tab keeps started, unfinished books, most recent first")
    func continueBooks() {
        let fresh = AudiobookModel(title: "Fresh", author: "A")
        let old = AudiobookModel(title: "Old", author: "A", currentPosition: 10, lastPlayed: Date(timeIntervalSince1970: 1))
        let recent = AudiobookModel(title: "Recent", author: "A", currentPosition: 10, lastPlayed: Date(timeIntervalSince1970: 2))
        let done = AudiobookModel(title: "Done", author: "A", currentPosition: 10, isFinished: true, lastPlayed: Date())

        let books = CarPlayLibrary.continueBooks([fresh, old, done, recent])
        #expect(books.map(\.title) == ["Recent", "Old"])
    }

    @Test("Library tab sorts by title, numerically aware")
    func libraryBooks() {
        let books = CarPlayLibrary.libraryBooks([
            AudiobookModel(title: "Book 10", author: "A"),
            AudiobookModel(title: "book 2", author: "A"),
            AudiobookModel(title: "Abc", author: "A")
        ])
        #expect(books.map(\.title) == ["Abc", "book 2", "Book 10"])
    }
}
