import SwiftUI

/// Where a server shelf leads. Pushed on the library's navigation stack.
enum AudiobookShelfRoute: Hashable {
    case series(AudiobookShelfAPI.Series)
    case author(AudiobookShelfAPI.Author)
}

/// A server series on the shelf, drawn like `CollectionCardView`: name, count, the first
/// covers overlapping, and the total length.
struct AudiobookShelfSeriesCard: View {
    let series: AudiobookShelfAPI.Series
    /// The count when the books did not come with the series (a collapsed entry).
    var bookCount: Int?

    /// In the server's order, which is series order: the books the series list sends carry
    /// no sequence of their own to sort by.
    private var books: [AudiobookShelfAPI.Item] { series.books ?? [] }

    /// The series list leaves `totalDuration` empty; the books still have theirs.
    private var duration: Double {
        series.totalDuration ?? books.compactMap(\.media.duration).reduce(0, +)
    }

    var body: some View {
        NavigationLink(value: AudiobookShelfRoute.series(series)) {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tint)
                    Text(series.name)
                        .font(.system(size: 17, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(countLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(.quaternary, in: Capsule())
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

                if !books.isEmpty {
                    HStack(spacing: 13) {
                        HStack(spacing: -14) {
                            ForEach(books.prefix(3)) { book in
                                AudiobookShelfCover(item: book.id, size: 44, cornerRadius: 8)
                            }
                        }
                        if duration > 0 {
                            Text(duration.hoursMinutesFormatted)
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(16)
            .contentShape(Rectangle())
            .glassCard(cornerRadius: 28)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { withHapticFeedback {} })
        .audiobookShelfDownloadAllMenu(.series(series.id), name: series.name)
    }

    private var countLabel: String {
        String(
            format: NSLocalizedString("%d books", comment: "AudiobookShelf: number of books in a series or by an author"),
            bookCount ?? books.count
        )
    }
}

/// A series' books in series order, fetched through the series filter: it is the one request
/// whose books carry their sequence, which the "Book 3" labels and the order need.
struct AudiobookShelfSeriesView: View {
    let series: AudiobookShelfAPI.Series
    let library: String

    @State private var books: [AudiobookShelfAPI.Item]?
    @State private var error: String?

    var body: some View {
        AudiobookShelfBookGrid(items: books ?? [], showsSequence: true)
            .overlay {
                if let error, books == nil {
                    ContentUnavailableView(
                        NSLocalizedString("Couldn't Load Library", comment: "AudiobookShelf load failure title"),
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if books == nil {
                    ProgressView()
                }
            }
            .navigationTitle(series.name)
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
    }

    private func load() async {
        guard books == nil else { return }
        let service = AudiobookShelfService.shared
        guard let server = service.server, let token = service.token else { return }
        do {
            books = try await AudiobookShelfAPI.seriesItems(server: server, token: token, library: library, series: series.id)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// An author's books by title.
struct AudiobookShelfAuthorView: View {
    let author: AudiobookShelfAPI.Author
    let library: String

    @State private var books: [AudiobookShelfAPI.Item]?
    @State private var error: String?

    var body: some View {
        AudiobookShelfBookGrid(items: books ?? [])
            .overlay {
                if let error, books == nil {
                    ContentUnavailableView(
                        NSLocalizedString("Couldn't Load Library", comment: "AudiobookShelf load failure title"),
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if books == nil {
                    ProgressView()
                }
            }
            .navigationTitle(author.name)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                let service = AudiobookShelfService.shared
                guard books == nil, let server = service.server, let token = service.token else { return }
                do {
                    books = try await AudiobookShelfAPI.authorItems(
                        server: server, token: token, library: library, author: author.id
                    )
                } catch {
                    self.error = error.localizedDescription
                }
            }
    }
}

/// A scrolling grid of server books at the library's grid density. `onReachEnd` pages.
struct AudiobookShelfBookGrid: View {
    let items: [AudiobookShelfAPI.Item]
    var showsSequence = false
    var onReachEnd: ((AudiobookShelfAPI.Item) -> Void)?

    var body: some View {
        ScrollView {
            AudiobookShelfBookGridContent(items: items, showsSequence: showsSequence, onReachEnd: onReachEnd)
                .padding(16)
        }
        .scrollContentBackground(.hidden)
        .background(TintedBackground(intensity: 0.6))
        .environment(\.audiobookShelfLibraryBooks, AudiobookShelfService.shared.libraryBooks)
    }
}

/// The grid itself, for callers that already scroll.
struct AudiobookShelfBookGridContent: View {
    let items: [AudiobookShelfAPI.Item]
    var showsSequence = false
    var onReachEnd: ((AudiobookShelfAPI.Item) -> Void)?

    @AppStorage("library.gridColumns") private var gridColumns = 2

    var body: some View {
        let spacing: CGFloat = gridColumns >= 4 ? 10 : 16
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 300 / CGFloat(gridColumns)), spacing: spacing)],
            spacing: spacing
        ) {
            ForEach(items) { item in
                Group {
                    if let collapsed = item.collapsedSeries {
                        AudiobookShelfCollapsedSeriesTile(item: item, series: collapsed, columns: gridColumns)
                    } else {
                        AudiobookShelfBookTile(item: item, columns: gridColumns, showsSequence: showsSequence)
                    }
                }
                .onAppear { onReachEnd?(item) }
            }
        }
    }
}

/// A whole series standing in the book grid, when the list folds series: the first book's
/// cover on a stack, the series name and its count.
struct AudiobookShelfCollapsedSeriesTile: View {
    let item: AudiobookShelfAPI.Item
    let series: AudiobookShelfAPI.Item.CollapsedSeries
    var columns = 2

    var body: some View {
        NavigationLink(value: AudiobookShelfRoute.series(AudiobookShelfAPI.Series(id: series.id, name: series.name))) {
            VStack(alignment: .leading, spacing: 8) {
                AudiobookShelfCover(item: item.id, title: series.name)
                    .background(alignment: .top) {
                        // The stack: two card edges peeking above the cover.
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.quaternary)
                            .padding(.horizontal, 10)
                            .offset(y: -6)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Label(String(series.numBooks), systemImage: "books.vertical.fill")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(.black.opacity(0.55), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(6)
                    }

                Text(series.name)
                    .font(.system(size: columns >= 3 ? 11.5 : 12.5, weight: .semibold))
                    .lineLimit(columns >= 4 ? 1 : 2)
                    .multilineTextAlignment(.leading)

                if columns < 4 {
                    Text(String(
                        format: NSLocalizedString("%d books", comment: "AudiobookShelf: number of books in a series or by an author"),
                        series.numBooks
                    ))
                    .font(.system(size: columns >= 3 ? 10 : 11))
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { withHapticFeedback {} })
        .audiobookShelfDownloadAllMenu(.series(series.id), name: series.name)
    }
}
