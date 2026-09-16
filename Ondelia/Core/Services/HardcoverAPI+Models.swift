import Foundation

// MARK: - Responses

extension HardcoverAPI {
    /// One book from search. `search.results` is a raw Typesense payload, hence the nesting.
    struct SearchHit: Decodable, Identifiable, Hashable {
        let id: Int
        let title: String
        let authorNames: [String]
        let image: Artwork?

        var author: String { authorNames.first ?? "" }
        var artworkURL: URL? { image?.url.flatMap(URL.init(string:)) }

        struct Artwork: Decodable, Hashable {
            let url: String?
        }

        enum CodingKeys: String, CodingKey {
            case id, title, image
            case authorNames = "author_names"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Typesense returns the id as a string on some indexes and a number on others.
            if let text = try? container.decode(String.self, forKey: .id) {
                guard let value = Int(text) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .id, in: container, debugDescription: "Invalid id string: \(text)"
                    )
                }
                id = value
            } else {
                id = try container.decode(Int.self, forKey: .id)
            }
            title = try container.decode(String.self, forKey: .title)
            authorNames = (try? container.decode([String].self, forKey: .authorNames)) ?? []
            image = try container.decodeIfPresent(Artwork.self, forKey: .image)
        }
    }

    struct SearchResponse: Decodable {
        let search: Results

        struct Results: Decodable {
            /// Null, with no `errors`, when Hardcover's search backend is down.
            let results: Hits?

            struct Hits: Decodable {
                let hits: [Hit]

                struct Hit: Decodable {
                    let document: SearchHit
                }
            }
        }
    }

    /// The blurb and the reader-applied tags for one book.
    struct BookDetails: Hashable, Sendable {
        let summary: String?
        let genres: [String]
        let moods: [String]
        let contentWarnings: [String]
        let releaseDate: Date?
    }

    struct BookDetailsResponse: Decodable {
        let books: [Book]

        struct Book: Decodable {
            let description: String?
            /// `release_date` is a plain "YYYY-MM-DD", nil when Hardcover does not know it.
            let releaseDate: String?
            /// `cached_tags` is a free-form jsonb column: a bucket per category, each holding
            /// rows that carry a `tag` among other fields. Anything that does not fit that
            /// shape is dropped rather than failing the whole decode.
            let cachedTags: [String: [Tag]]

            struct Tag: Decodable {
                let tag: String
            }

            func tags(in category: String) -> [String] {
                (cachedTags[category] ?? []).map(\.tag)
            }

            enum CodingKeys: String, CodingKey {
                case description
                case cachedTags = "cached_tags"
                case releaseDate = "release_date"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                description = try? container.decodeIfPresent(String.self, forKey: .description)
                releaseDate = try? container.decodeIfPresent(String.self, forKey: .releaseDate)
                cachedTags = (try? container.decodeIfPresent([String: [Tag]].self, forKey: .cachedTags)) ?? [:]
            }
        }
    }

    /// Where one book sits in one series.
    struct SeriesRef: Hashable, Sendable, Identifiable {
        let id: Int
        let name: String
        let position: Double?
    }

    struct SeriesVolumesResponse: Decodable {
        let series: [Entry]

        struct Entry: Decodable {
            let bookSeries: [Volume]

            enum CodingKeys: String, CodingKey {
                case bookSeries = "book_series"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                bookSeries = (try? container.decode([Volume].self, forKey: .bookSeries)) ?? []
            }
        }

        struct Volume: Decodable {
            let position: Double?
            let book: Book

            struct Book: Decodable {
                let id: Int
                let title: String
                let image: SearchHit.Artwork?
            }

            enum CodingKeys: String, CodingKey {
                case position, book
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                book = try container.decode(Book.self, forKey: .book)
                position = try container.decodeSeriesPosition(forKey: .position)
            }
        }
    }

    struct BookSeriesResponse: Decodable {
        let books: [Book]

        struct Book: Decodable {
            let bookSeries: [Entry]

            enum CodingKeys: String, CodingKey {
                case bookSeries = "book_series"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                bookSeries = (try? container.decode([Entry].self, forKey: .bookSeries)) ?? []
            }
        }

        struct Entry: Decodable {
            /// Hardcover stores the position as a number on some rows and a string on others.
            let position: Double?
            let series: Series

            struct Series: Decodable {
                let id: Int
                let name: String
            }

            enum CodingKeys: String, CodingKey {
                case position, series
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                series = try container.decode(Series.self, forKey: .series)
                position = try container.decodeSeriesPosition(forKey: .position)
            }
        }
    }

    struct InsertUserBookResponse: Decodable {
        let insertUserBook: Row

        struct Row: Decodable {
            let id: Int
        }

        enum CodingKeys: String, CodingKey {
            case insertUserBook = "insert_user_book"
        }
    }

    struct DeleteUserBookResponse: Decodable {
        let deleteUserBook: Row?

        struct Row: Decodable {
            let bookID: Int

            enum CodingKeys: String, CodingKey {
                case bookID = "book_id"
            }
        }

        enum CodingKeys: String, CodingKey {
            case deleteUserBook = "delete_user_book"
        }
    }
}

// MARK: - Shared decoding

private extension KeyedDecodingContainer {
    /// Hardcover writes the series position as a number on some rows and a string on others,
    /// and omits it for a volume whose place is unrecorded.
    func decodeSeriesPosition(forKey key: Key) throws -> Double? {
        if let number = try? decodeIfPresent(Double.self, forKey: key) { return number }
        guard let text = try? decodeIfPresent(String.self, forKey: key) else { return nil }
        return Double(text)
    }
}
