import Foundation

/// The Hardcover book an audiobook is linked to.
///
/// Stored as one Codable attribute on `AudiobookModel` rather than a related `@Model`: nothing
/// queries or sorts on it, and a link has no life of its own once its audiobook is deleted.
struct HardcoverLink: Codable, Hashable, Sendable {
    /// Where the book sits in the reader's Hardcover shelves.
    ///
    /// Ordered, and syncs only ever move a book forward. Without that, re-opening a finished
    /// book would push it back to "currently reading" on the reader's profile.
    enum Status: Int, Codable, Comparable, Sendable {
        /// Linked in this app only, never sent to Hardcover.
        case local = 0
        case wantToRead = 1
        case reading = 2
        case read = 3

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let id: Int
    var title: String
    var author: String
    var artworkURL: URL?
    var status: Status
    /// Id of the shelf row on Hardcover. Needed to take the book off the shelf again, and nil
    /// until the book has actually been put on one.
    var userBookID: Int?

    init(
        id: Int,
        title: String,
        author: String,
        artworkURL: URL? = nil,
        status: Status = .local,
        userBookID: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.artworkURL = artworkURL
        self.status = status
        self.userBookID = userBookID
    }
}
