import SwiftUI
import UIKit

struct SearchView: View {
    @Binding var query: String
    private let audiobookManager = AudiobookManager.shared
    @Environment(\.playerRouter) private var playerRouter
    @State private var debouncedQuery: String = ""
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var filter: Filter = .all
    @State private var sort: Sort = .relevance

    private var results: [AudiobookModel] {
        let q = normalize(debouncedQuery)
        guard !q.isEmpty else { return [] }

        var items = audiobookManager.audiobooks
        // Filter facet
        items = items.filter { book in
            switch filter {
            case .all: return true
            case .inProgress: return book.currentPosition > 0 && !book.isFinished
            case .completed: return book.isFinished
            case .notStarted: return book.currentPosition == 0
            }
        }

        // Query match
        items = items.filter { book in
            let t = normalize(book.title ?? "")
            let a = normalize(book.author ?? "")
            let n = normalize(book.narrator ?? "")
            return t.contains(q) || a.contains(q) || n.contains(q)
        }

        // Relevance weight
        func weight(for book: AudiobookModel) -> Int {
            let t = normalize(book.title ?? "")
            let a = normalize(book.author ?? "")
            let n = normalize(book.narrator ?? "")
            var w = 0
            if t == q { w += 100 }
            if a == q { w += 80 }
            if t.contains(q) { w += 40 }
            if a.contains(q) { w += 30 }
            if n.contains(q) { w += 10 }
            return w
        }

        switch sort {
        case .relevance:
            items.sort { weight(for: $0) > weight(for: $1) }
        case .recent:
            items.sort { $0.lastPlayed > $1.lastPlayed }
        case .title:
            items.sort { ($0.title ?? "") < ($1.title ?? "") }
        case .author:
            items.sort { ($0.author ?? "") < ($1.author ?? "") }
        case .progress:
            items.sort {
                let p0 = (($0.duration > 0) ? $0.currentPosition / $0.duration : 0)
                let p1 = (($1.duration > 0) ? $1.currentPosition / $1.duration : 0)
                return p0 > p1
            }
        }

        return items
    }

    // Normalize strings for case- and accent-insensitive comparison
    private func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private var filtersActive: Bool { filter != .all || sort != .relevance }

    var body: some View {
        NavigationStack {
            List {
                // Persistent header (chips + sort) — always visible
                header

                if debouncedQuery.isEmpty {
                    EmptyRowView(
                        title: NSLocalizedString("Search your audiobooks", comment: "Search empty title"),
                        message: NSLocalizedString("Type a title or author to find a book in your library.", comment: "Search empty message")
                    )
                    .listRowSeparator(.hidden)
                } else if results.isEmpty {
                    EmptyRowView(
                        title: NSLocalizedString("No results", comment: "No results title"),
                        message: NSLocalizedString("Try a different term or check spelling.", comment: "No results message")
                    )
                    .listRowSeparator(.hidden)
                    if filtersActive {
                        HStack {
                            Spacer()
                            Button {
                                resetFilters()
                            } label: {
                                Label(NSLocalizedString("Clear Filters", comment: "Clear filters button"), systemImage: "line.3.horizontal.decrease.circle")
                            }
                            .buttonStyle(.bordered)
                            .tint(.accentColor)
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                    }
                } else {
                    ForEach(results, id: \.id) { book in
                        SearchResultRow(audiobook: book, query: debouncedQuery)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                let audio = GlobalAudioManager.shared
                                audio.loadAudiobook(book)
                                audio.startPlayback()
                                playerRouter?.present(book)
                            }
                            .swipeActions(edge: .leading) {
                                Button(book.isFinished ? NSLocalizedString("Mark Unread", comment: "Mark as unread") : NSLocalizedString("Mark Read", comment: "Mark as read")) {
                                    if book.isFinished { audiobookManager.markAsUnread(book) } else { audiobookManager.markAsRead(book) }
                                }.tint(book.isFinished ? .orange : .green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(NSLocalizedString("Delete", comment: "Delete button"), role: .destructive) {
                                    audiobookManager.deleteAudiobook(book)
                                }
                            }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(NSLocalizedString("Search", comment: "Search view title"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if audiobookManager.audiobooks.isEmpty && !audiobookManager.isLoadingLibrary {
                    audiobookManager.fetchAudiobooks()
                }
            }
            .onChange(of: query) { _, newValue in
                searchTask?.cancel()
                searchTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    self.debouncedQuery = newValue
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Picker(NSLocalizedString("Filter", comment: "Search filter picker label"), selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { f in Text(f.label).tag(f) }
            }
            .pickerStyle(.segmented)

            Spacer(minLength: 8)

            Menu {
                Picker(NSLocalizedString("Sort by", comment: "Search sort picker label"), selection: $sort) {
                    ForEach(Sort.allCases, id: \.self) { s in Text(s.label).tag(s) }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }

            if filtersActive {
                Button {
                    resetFilters()
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

    private func resetFilters() {
        filter = .all
        sort = .relevance
    }
}

// MARK: - Facets & Sorts
private enum Filter: CaseIterable { case all, inProgress, completed, notStarted
    var label: String {
        switch self {
        case .all: return NSLocalizedString("All", comment: "Filter: all audiobooks")
        case .inProgress: return NSLocalizedString("In Progress", comment: "Filter: books in progress")
        case .completed: return NSLocalizedString("Completed", comment: "Filter: completed books")
        case .notStarted: return NSLocalizedString("Not Started", comment: "Filter: books not started")
        }
    }
}

private enum Sort: CaseIterable { case relevance, recent, title, author, progress
    var label: String {
        switch self {
        case .relevance: return NSLocalizedString("Relevance", comment: "Sort by relevance")
        case .recent: return NSLocalizedString("Recently Played", comment: "Sort by recently played")
        case .title: return NSLocalizedString("Title", comment: "Sort by title")
        case .author: return NSLocalizedString("Author", comment: "Sort by author")
        case .progress: return NSLocalizedString("Progress", comment: "Sort by progress")
        }
    }
}
