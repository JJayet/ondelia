import Foundation
import SwiftData

/// One stretch of listening: what played, when it started, and how many wall-clock seconds
/// were spent. Speed is already accounted for — a 12 h book at 2× is six hours of sessions.
///
/// Everything the statistics screen shows is derived from these rows, so the row carries a
/// copy of the book's title, author, narrator and genres rather than a relationship: deleting
/// the book must not delete the hours that went into it. CloudKit-compatible: defaults on all.
@Model
final class ListeningSessionModel {
    var id: UUID = UUID()
    var bookID: UUID = UUID()
    var title: String = ""
    var author: String?
    var narrator: String?
    var genres: [String] = []
    var startedAt: Date = Date()
    var seconds: Double = 0
    /// The session during which the book was finished. A book marked finished by hand gets a
    /// zero-second session with this set, so completions survive the book's deletion too.
    var finishedBook: Bool = false

    init(book: AudiobookModel, startedAt: Date = Date(), seconds: Double = 0, finishedBook: Bool = false) {
        self.bookID = book.id
        self.title = book.title ?? ""
        self.author = book.author
        self.narrator = book.narrator
        self.genres = book.hardcover?.genres ?? []
        self.startedAt = startedAt
        self.seconds = seconds
        self.finishedBook = finishedBook
    }
}
