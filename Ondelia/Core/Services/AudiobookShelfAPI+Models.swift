import Foundation

extension AudiobookShelfAPI {
    struct Library: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
        let mediaType: String
    }

    /// A book's place in one series. `sequence` is free text: "1", "1.5", "Prequel".
    struct SeriesSequence: Codable, Hashable {
        let id: String
        let name: String?
        let sequence: String?
    }

    struct Item: Codable, Identifiable, Hashable {
        struct Media: Codable, Hashable {
            struct Metadata: Codable, Hashable {
                struct Author: Codable, Hashable { let name: String }
                let title: String?
                /// Filled by the minified item list.
                let authorName: String?
                /// Filled by search, which returns expanded items instead.
                let authors: [Author]?
                /// "Name #1, Other #2", filled by the minified item list.
                let seriesName: String?
                /// The series this book was fetched through, when it was: filtering by series
                /// fills it. Expanded items list every series instead, and the first one is kept.
                let series: SeriesSequence?
                /// The publisher's blurb and the server's genres: what recommendations read.
                let description: String?
                let genres: [String]?

                private enum CodingKeys: String, CodingKey {
                    case title, authorName, authors, seriesName, series, description, genres
                }

                init(from decoder: any Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    title = try container.decodeIfPresent(String.self, forKey: .title)
                    authorName = try container.decodeIfPresent(String.self, forKey: .authorName)
                    authors = try? container.decodeIfPresent([Author].self, forKey: .authors)
                    seriesName = try? container.decodeIfPresent(String.self, forKey: .seriesName)
                    series = (try? container.decodeIfPresent(SeriesSequence.self, forKey: .series))
                        ?? (try? container.decodeIfPresent([SeriesSequence].self, forKey: .series))?.first
                    description = try? container.decodeIfPresent(String.self, forKey: .description)
                    genres = try? container.decodeIfPresent([String].self, forKey: .genres)
                }

                /// For the catalogue's disk cache; reads back through `init(from:)`.
                func encode(to encoder: any Encoder) throws {
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    try container.encodeIfPresent(title, forKey: .title)
                    try container.encodeIfPresent(authorName, forKey: .authorName)
                    try container.encodeIfPresent(authors, forKey: .authors)
                    try container.encodeIfPresent(seriesName, forKey: .seriesName)
                    try container.encodeIfPresent(series, forKey: .series)
                    try container.encodeIfPresent(description, forKey: .description)
                    try container.encodeIfPresent(genres, forKey: .genres)
                }
            }
            let metadata: Metadata
            let duration: Double?
        }

        /// Present when the list was asked to fold series: this entry stands for the series.
        struct CollapsedSeries: Codable, Hashable {
            let id: String
            let name: String
            let numBooks: Int
        }

        let id: String
        let media: Media
        let collapsedSeries: CollapsedSeries?
        /// When the server got the book, in milliseconds since 1970.
        var addedAt: Double?
        /// The book's files, in bytes: what a download will weigh when the server zips it
        /// without saying.
        var size: Int64?

        var dateAdded: Date { Date(timeIntervalSince1970: (addedAt ?? 0) / 1000) }

        var title: String { media.metadata.title ?? "" }

        var author: String? {
            if let name = media.metadata.authorName, !name.isEmpty { return name }
            let names = media.metadata.authors?.map(\.name).joined(separator: ", ")
            return names?.isEmpty == false ? names : nil
        }

        var sequence: String? {
            guard let sequence = media.metadata.series?.sequence, !sequence.isEmpty else { return nil }
            return sequence
        }

        /// Series order: by sequence the way Finder sorts numbers ("2" before "10"), books
        /// without one last, then by title.
        static func bySequence(_ lhs: Item, _ rhs: Item) -> Bool {
            switch (lhs.sequence, rhs.sequence) {
            case let (left?, right?) where left != right:
                return left.localizedStandardCompare(right) == .orderedAscending
            case (.some, nil): return true
            case (nil, .some): return false
            default: return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        }
    }

    struct Series: Codable, Identifiable, Hashable {
        let id: String
        let name: String
        /// Filled by the series list and search, in series order but without their sequence.
        var books: [Item]?
        var totalDuration: Double?
        /// A server collection, drawn as a series: a named, ordered list of books. Its books come
        /// with it, so nothing is fetched to open it.
        var isCollection: Bool?

        var isServerCollection: Bool { isCollection == true }
        var hiddenKind: HiddenServerEntryModel.Kind { isServerCollection ? .collection : .series }
    }

    struct Author: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
        let numBooks: Int?
        let imagePath: String?
    }

    struct SearchResults: Equatable {
        var books: [Item] = []
        var series: [Series] = []
        var authors: [Author] = []

        var isEmpty: Bool { books.isEmpty && series.isEmpty && authors.isEmpty }
    }
}
