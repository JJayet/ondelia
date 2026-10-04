import Foundation

extension Recommender {
    /// A book that can be picked: one in the Library, or a server book it has not joined.
    struct Candidate: Identifiable {
        enum Source {
            case book(AudiobookModel)
            case server(AudiobookShelfAPI.Item)
        }

        let source: Source
        let title: String
        let author: String?
        /// "The Expanse #2", or the series' name alone.
        let series: String?
        let genres: [String]
        let blurb: String

        var id: String {
            switch source {
            case .book(let book): book.id.uuidString
            case .server(let item): item.id
            }
        }

        init(_ item: AudiobookShelfAPI.Item) {
            source = .server(item)
            title = item.title
            author = item.author
            series = item.media.metadata.seriesName ?? item.media.metadata.series?.name
            genres = item.media.metadata.genres ?? []
            blurb = item.media.metadata.description ?? ""
        }

        /// `series`: the name of the series Collection holding it, when there is one.
        init(_ book: AudiobookModel, series: String? = nil) {
            source = .book(book)
            title = book.title ?? ""
            author = book.author
            self.series = series ?? book.hardcover?.seriesName
            genres = book.hardcover?.genres ?? []
            blurb = book.hardcover?.summary ?? ""
        }
    }

    enum Failure: LocalizedError {
        case noHistory

        var errorDescription: String? {
            switch self {
            case .noHistory:
                NSLocalizedString("Listen to a book or two first: picks are based on what you played.", comment: "Recommendations: no listening history yet")
            }
        }
    }

    /// Less than this and a book was only sampled: it says nothing about taste.
    static let sampleThreshold: TimeInterval = 30 * 60

    /// Books listened to for real, most recently played first.
    static func history(_ books: [AudiobookModel]) -> [AudiobookModel] {
        books.filter { $0.isFinished || $0.currentPosition >= sampleThreshold }
            .sorted { $0.lastPlayed > $1.lastPlayed }
    }

    static func isStarted(_ book: AudiobookModel) -> Bool { book.currentPosition > 0 || book.isFinished }

    /// Whether the picks would hold a book: something listened to, and a book to continue or
    /// one not started yet, in the Library or on the server.
    static func hasPicks(books: [AudiobookModel], hasServerBooks: Bool) -> Bool {
        let history = history(books)
        guard !history.isEmpty else { return false }
        return history.contains { !$0.isFinished } || hasServerBooks || books.contains { !isStarted($0) }
    }

    /// The series Collections: Hardcover's and the server's.
    static func seriesCollections(_ collections: [CollectionModel]) -> [CollectionModel] {
        collections.filter { $0.isSeries || AudiobookShelfCatalog.shared.seriesByCollection[$0.id] != nil }
    }

    /// "The Final Empire [Abridged]" and "The Final Empire (Unabridged)" are the same book.
    static func normalizedTitle(_ title: String) -> String {
        title.replacingOccurrences(of: #"\s*[\[(][^\])]*[\])]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
    }
}
