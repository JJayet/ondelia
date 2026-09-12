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
    /// Audiobook edition Hardcover should measure progress against. Seconds are meaningless
    /// without one: the percentage is `progress_seconds` over that edition's length.
    var editionID: Int?
    /// Whether Hardcover has been asked for an audiobook edition. A book that has none is a
    /// real answer, so nil-vs-asked cannot be told apart without this.
    var editionChecked: Bool?
    /// The `user_book_reads` row this listening is being written to. Nil until the first push;
    /// after that the row is moved rather than a second one opened.
    var readID: Int?
    /// Hardcover's id for that series, so the rest of its volumes can be looked up.
    var seriesID: Int?
    /// Series this book belongs to, as Hardcover has it. Nil for a standalone book, and also
    /// nil for a link made before the series lookup existed — `HardcoverService.refreshSeries`
    /// fills those in.
    var seriesName: String?
    /// Where the book sits in its series. Hardcover allows halves (a 1.5 novella), so this is
    /// not an Int.
    var seriesPosition: Double?
    /// What Hardcover knows about the book itself, filled in the first time its detail screen
    /// is opened. Optional throughout: a link written before this existed decodes unchanged.
    var summary: String?
    var genres: [String]?
    var moods: [String]?
    var contentWarnings: [String]?
    /// First publication date as Hardcover has it, for ordering a collection by it.
    var releaseDate: Date?
    /// Whether Hardcover has been asked for the release date. Links written before the field
    /// existed have `detailsChecked` set and no date, so they are asked once more.
    var releaseDateChecked: Bool?
    /// Whether Hardcover has been asked for the above. A book with no description at all is a
    /// real answer, so nil-vs-asked cannot be told apart without this.
    var detailsChecked: Bool?
    /// Whether Hardcover has been asked about this book's series. Without it, every standalone
    /// book would be asked about again on every launch, since a nil `seriesName` is also the
    /// right answer for a book that is in no series.
    var seriesChecked: Bool?

    init(
        id: Int,
        title: String,
        author: String,
        artworkURL: URL? = nil,
        status: Status = .local,
        userBookID: Int? = nil,
        editionID: Int? = nil,
        editionChecked: Bool? = nil,
        readID: Int? = nil,
        seriesID: Int? = nil,
        seriesName: String? = nil,
        seriesPosition: Double? = nil,
        seriesChecked: Bool? = nil,
        summary: String? = nil,
        genres: [String]? = nil,
        moods: [String]? = nil,
        contentWarnings: [String]? = nil,
        detailsChecked: Bool? = nil,
        releaseDate: Date? = nil,
        releaseDateChecked: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.artworkURL = artworkURL
        self.status = status
        self.userBookID = userBookID
        self.editionID = editionID
        self.editionChecked = editionChecked
        self.readID = readID
        self.seriesID = seriesID
        self.seriesName = seriesName
        self.seriesPosition = seriesPosition
        self.seriesChecked = seriesChecked
        self.summary = summary
        self.genres = genres
        self.moods = moods
        self.contentWarnings = contentWarnings
        self.detailsChecked = detailsChecked
        self.releaseDate = releaseDate
        self.releaseDateChecked = releaseDateChecked
    }

    /// The compact volume badge — "#1", or "#1.5" for a novella between two volumes.
    var volumeBadge: String? {
        guard let seriesPosition else { return nil }
        let rounded = seriesPosition.rounded()
        return rounded == seriesPosition
            ? "#\(Int(rounded))"
            : "#\(seriesPosition.formatted(.number.precision(.fractionLength(0...1))))"
    }
}
