import SwiftUI
import UIKit

struct SearchView: View {
    @Binding var query: String
    private let audiobookManager = AudiobookManager.shared
    private let catalog = AudiobookShelfCatalog.shared
    /// Redraws the results when server audiobooks are switched on or off.
    @AppStorage(AudiobookShelfCatalog.enabledKey) private var blendsServer = false
    @Environment(\.playerRouter) private var playerRouter
    @Environment(\.isFoldSplit) var isFoldSplit
    @State var debouncedQuery: String = ""
    @State private var searchTask: Task<Void, Never>? = nil
    @State var filter: SearchFilter = .all
    @State var sort: SearchSort = .relevance
    /// The last searches that led to a book, newest first, one per line.
    @AppStorage("search.recent") var recentSearches = ""
    /// An author picked from the results around the fold: only their books are shown.
    @State var pickedAuthor: String?
    /// The book a swipe asked to delete, waiting on the confirmation.
    @State private var pendingDelete: AudiobookModel?

    /// Library books and, when shown beside them, server audiobooks not in the Library
    /// (ADR 0002). Server audiobooks have never been played, so they count as not started.
    func entries(for filter: SearchFilter) -> [LibraryEntry] {
        let linked = AudiobookShelfService.shared.libraryBooks
        let books = catalog.visible(audiobookManager.audiobooks, linked: linked).filter(filter.includes)
        let server = filter == .all || filter == .notStarted ? catalog.unjoined(linked: linked) : []
        return books.map(LibraryEntry.book) + server.map(LibraryEntry.server)
    }

    /// Read once per render and handed down: each read filters and sorts again.
    var results: [LibraryEntry] {
        let q = normalize(debouncedQuery)
        guard !q.isEmpty else { return [] }

        // Query match, narrowed to the picked author's books when there is one, each entry
        // normalized once rather than on every comparison.
        var items: [(entry: LibraryEntry, weight: Int)] = entries(for: filter).compactMap { entry in
            if let pickedAuthor, !Self.authorNames(entry.author).contains(pickedAuthor) { return nil }
            let t = normalize(entry.title)
            let a = normalize(entry.author)
            let n = normalize(entry.narrator)
            guard t.contains(q) || a.contains(q) || n.contains(q) else { return nil }
            // Relevance weight
            var w = 0
            if t == q { w += 100 }
            if a == q { w += 80 }
            if t.contains(q) { w += 40 }
            if a.contains(q) { w += 30 }
            if n.contains(q) { w += 10 }
            return (entry, w)
        }

        func book(_ item: (entry: LibraryEntry, weight: Int)) -> AudiobookModel? { item.entry.book }
        switch sort {
        case .relevance:
            items.sort { $0.weight > $1.weight }
        case .recent:
            // Never played: server audiobooks last.
            items.sort { (book($0)?.lastPlayed ?? .distantPast) > (book($1)?.lastPlayed ?? .distantPast) }
        case .title:
            items.sort { $0.entry.title.localizedStandardCompare($1.entry.title) == .orderedAscending }
        case .author:
            items.sort { $0.entry.author.localizedStandardCompare($1.entry.author) == .orderedAscending }
        case .progress:
            items.sort { (book($0)?.progressFraction ?? 0) > (book($1)?.progressFraction ?? 0) }
        }

        return items.map(\.entry)
    }

    // Normalize strings for case- and accent-insensitive comparison
    func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private var filtersActive: Bool { filter != .all || sort != .relevance }

    var body: some View {
        // Around the fold the left half carries its own field: the system's would cross it.
        if isFoldSplit {
            stack
        } else {
            stack.searchable(text: $query)
        }
    }

    private var stack: some View {
        let results = results
        return NavigationStack {
            // iPhone Duo around its fold (design 12): the question on the left, the answer on
            // the right, so typing never moves the field, the filter or the sort.
            FoldSplit {
                foldQuestion
            } secondary: {
                foldAnswer(results)
            } fallback: {
                List {
                    // Persistent header (chips + sort) — always visible
                    header

                    if debouncedQuery.isEmpty {
                        emptyPrompt.listRowSeparator(.hidden)
                    } else if results.isEmpty {
                        noResults
                    } else {
                        resultRows(results)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle(NSLocalizedString("Search", comment: "Search view title"))
            .navigationBarTitleDisplayMode(.inline)
            // The left half titles itself; an inline title would sit on the fold.
            .toolbar(isFoldSplit ? .hidden : .automatic, for: .navigationBar)
            .onAppear {
                if audiobookManager.audiobooks.isEmpty && !audiobookManager.isLoadingLibrary {
                    audiobookManager.fetchAudiobooks()
                }
            }
            // The Library screen usually fetched the catalogue already; not when Search came first.
            .task(id: blendsServer) {
                await catalog.refresh()
            }
            .onChange(of: query) { _, newValue in
                searchTask?.cancel()
                searchTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    self.debouncedQuery = newValue
                    self.pickedAuthor = nil
                }
            }
            .alert(
                NSLocalizedString("Delete Audiobook", comment: "Delete confirmation alert title"),
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                presenting: pendingDelete
            ) { audiobook in
                Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {}
                Button(NSLocalizedString("Delete", comment: "Delete button"), role: .destructive) {
                    audiobookManager.deleteAudiobook(audiobook)
                }
            } message: { audiobook in
                Text(String(
                    format: NSLocalizedString(
                        "'%@', its progress and its bookmarks will be removed. This cannot be undone.",
                        comment: "Delete confirmation alert message"
                    ),
                    audiobook.title ?? AudiobookModel.unknownTitle
                ))
            }
        }
    }

    var emptyPrompt: some View {
        EmptyRowView(
            title: NSLocalizedString("Search your audiobooks", comment: "Search empty title"),
            message: NSLocalizedString("Type a title or author to find a book in your library.", comment: "Search empty message")
        )
    }

    @ViewBuilder
    var noResults: some View {
        EmptyRowView(
            title: NSLocalizedString("No results", comment: "No results title"),
            message: NSLocalizedString("Try a different term or check spelling.", comment: "No results message")
        )
        .listRowSeparator(.hidden)
        if filtersActive {
            HStack {
                Spacer()
                Button {
                    withHapticFeedback { resetFilters() }
                } label: {
                    Label(NSLocalizedString("Clear Filters", comment: "Clear filters button"), systemImage: "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
                Spacer()
            }
            .listRowSeparator(.hidden)
        }
    }

    func resultRows(_ results: [LibraryEntry]) -> some View {
        ForEach(results) { entry in
            switch entry {
            case .book(let book): bookRow(book)
            case .server(let item): serverRow(item)
            }
        }
    }

    private func bookRow(_ book: AudiobookModel) -> some View {
        SearchResultRow(entry: .book(book), query: debouncedQuery)
            .contentShape(Rectangle())
            .onTapGesture {
                withHapticFeedback(.medium) {
                    rememberSearch()
                    present(book)
                }
            }
            .swipeActions(edge: .leading) {
                Button(book.isFinished ? NSLocalizedString("Mark Unread", comment: "Mark as unread") : NSLocalizedString("Mark Read", comment: "Mark as read")) {
                    withHapticFeedback {
                        ListenerState.shared.apply(book.isFinished ? .unfinish : .finish, to: book, from: .listener)
                    }
                }.tint(book.isFinished ? .orange : .green)
            }
            // No full swipe, and a confirmation: as on the Library, deleting drops the book, its
            // progress and its bookmarks with nothing to undo.
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(NSLocalizedString("Delete", comment: "Delete button"), role: .destructive) {
                    withHapticFeedback { pendingDelete = book }
                }
                .tint(.red)
            }
    }

    /// Tapping streams it, which makes it join the Library, or downloads it, as `TapAction`
    /// says; a long press offers the other.
    private func serverRow(_ item: AudiobookShelfAPI.Item) -> some View {
        SearchResultRow(entry: .server(item), query: debouncedQuery)
            .contentShape(Rectangle())
            .onTapGesture {
                withHapticFeedback(.medium) {
                    rememberSearch()
                    AudiobookShelfService.shared.open(item, local: nil) { present($0) }
                }
            }
            .contextMenu {
                AudiobookShelfItemMenu(item: item, isOnDevice: false, joined: false)
                    .environment(\.audiobookShelfPlay, AudiobookShelfAction { present($0) })
            }
    }

    private func present(_ book: AudiobookModel) {
        let audio = GlobalAudioManager.shared
        audio.loadAudiobook(book)
        audio.resumePlayback()
        playerRouter?.present(book)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Picker(NSLocalizedString("Filter", comment: "Search filter picker label"), selection: $filter) {
                ForEach(SearchFilter.allCases, id: \.self) { f in Text(f.label).tag(f) }
            }
            .pickerStyle(.segmented)

            Spacer(minLength: 8)

            Menu {
                Picker(NSLocalizedString("Sort by", comment: "Search sort picker label"), selection: $sort) {
                    ForEach(SearchSort.allCases, id: \.self) { s in Text(s.label).tag(s) }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .accessibilityLabel(NSLocalizedString("Sort by", comment: "Search sort picker label"))
            .accessibilityValue(sort.label)

            if filtersActive {
                Button {
                    withHapticFeedback { resetFilters() }
                } label: {
                    Label(NSLocalizedString("Clear", comment: "Clear filters short label"), systemImage: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .tint(.accentColor)
                .font(.caption)
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    func resetFilters() {
        filter = .all
        sort = .relevance
    }
}
