import SwiftUI

/// One tab of the server shelf, paging as it scrolls.
struct AudiobookShelfTabContent: View {
    let tab: AudiobookShelfShelfView.Tab
    let shelves: AudiobookShelfShelves
    let library: String

    var body: some View {
        switch tab {
        case .books:
            paged(shelves.books) { items in
                AudiobookShelfBookGridContent(items: items) { item in
                    Task { await shelves.books.loadMore(after: item) }
                }
            }
        case .series:
            paged(shelves.series) { items in
                LazyVStack(spacing: 12) {
                    ForEach(items) { series in
                        AudiobookShelfSeriesCard(series: series)
                            .onAppear { Task { await shelves.series.loadMore(after: series) } }
                    }
                }
            }
        case .authors:
            paged(shelves.authors) { items in
                LazyVStack(spacing: 8) {
                    ForEach(items) { AudiobookShelfAuthorRow(author: $0) }
                }
            }
        }
    }

    /// The list, then a spinner or the error while more is coming, and the first page on appear.
    private func paged<Element: Identifiable, Content: View>(
        _ pager: AudiobookShelfPager<Element>,
        @ViewBuilder content: @escaping ([Element]) -> Content
    ) -> some View {
        VStack(spacing: 16) {
            content(pager.items)
            if let error = pager.error {
                VStack(spacing: 8) {
                    Text(error).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button(NSLocalizedString("Try Again", comment: "Retry loading button")) {
                        Task { await pager.loadMore() }
                    }
                }
                .frame(maxWidth: .infinity)
            } else if pager.isLoading || pager.total == nil {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
            } else if pager.items.isEmpty {
                ContentUnavailableView(
                    NSLocalizedString("No Books", comment: "AudiobookShelf empty library title"),
                    systemImage: "books.vertical"
                )
            }
        }
        .task(id: ObjectIdentifier(pager)) {
            if pager.items.isEmpty { await pager.loadMore() }
        }
    }
}

/// An author on the shelf: portrait, name, book count.
struct AudiobookShelfAuthorRow: View {
    let author: AudiobookShelfAPI.Author

    @State private var image: UIImage?

    var body: some View {
        NavigationLink(value: AudiobookShelfRoute.author(author)) {
            HStack(spacing: 12) {
                Circle()
                    .fill(.quaternary)
                    .overlay {
                        if let image = image ?? AudiobookShelfImages.cached(cacheKey) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Text(initials)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(author.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    if let count = author.numBooks {
                        Text(String(
                            format: NSLocalizedString("%d books", comment: "AudiobookShelf: number of books in a series or by an author"),
                            count
                        ))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .glassCard(cornerRadius: 18)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { withHapticFeedback {} })
        .audiobookShelfDownloadAllMenu(.author(author.id))
        .task(id: author.id) {
            // Most authors have no portrait; asking only for those that do saves a 404 each.
            guard author.imagePath != nil else { return }
            image = await AudiobookShelfImages.load(key: cacheKey) { server, token in
                AudiobookShelfAPI.authorImageRequest(server: server, token: token, author: author.id)
            }
        }
    }

    private var cacheKey: String { "author-\(author.id)" }

    private var initials: String {
        author.name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

/// What a search found: authors, then series, then books.
struct AudiobookShelfSearchResultsView: View {
    let results: AudiobookShelfAPI.SearchResults
    let query: String

    var body: some View {
        if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if !results.authors.isEmpty {
                    SectionLabel(NSLocalizedString("Authors", comment: "AudiobookShelf shelf tab: authors"))
                    ForEach(results.authors) { AudiobookShelfAuthorRow(author: $0) }
                }
                if !results.series.isEmpty {
                    SectionLabel(String(localized: "shelf.tab.series", defaultValue: "Series", comment: "AudiobookShelf shelf tab: series"))
                    ForEach(results.series) { AudiobookShelfSeriesCard(series: $0) }
                }
                if !results.books.isEmpty {
                    SectionLabel(NSLocalizedString("Books", comment: "AudiobookShelf shelf tab: books"))
                    AudiobookShelfBookGridContent(items: results.books)
                }
            }
        }
    }
}
