import SwiftUI
import UIKit

struct SearchView: View {
    @Binding var query: String
    @StateObject private var audiobookManager = AudiobookManager()
    @Environment(\.playerRouter) private var playerRouter
    @State private var debouncedQuery: String = ""
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var filter: Filter = .all
    @State private var sort: Sort = .relevance

    private var results: [AudiobookModel] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
            let t = (book.title ?? "").lowercased()
            let a = (book.author ?? "").lowercased()
            let n = (book.narrator ?? "").lowercased()
            return t.contains(q) || a.contains(q) || n.contains(q)
        }

        // Relevance weight
        func weight(for book: AudiobookModel) -> Int {
            let t = (book.title ?? "").lowercased()
            let a = (book.author ?? "").lowercased()
            let n = (book.narrator ?? "").lowercased()
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
                            }
                            .swipeActions(edge: .leading) {
                                Button(book.isFinished ? NSLocalizedString("Mark Unread", comment: "") : NSLocalizedString("Mark Read", comment: "")) {
                                    if book.isFinished { audiobookManager.markAsUnread(book) } else { audiobookManager.markAsRead(book) }
                                }.tint(book.isFinished ? .orange : .green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(NSLocalizedString("Delete", comment: "Delete"), role: .destructive) {
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
            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { f in Text(f.label).tag(f) }
            }
            .pickerStyle(.segmented)

            Spacer(minLength: 8)

            Menu {
                Picker("Sort by", selection: $sort) {
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

private struct SearchResultRow: View {
    let audiobook: AudiobookModel
    let query: String

    var body: some View {
        HStack(spacing: 12) {
            cover
            VStack(alignment: .leading, spacing: 6) {
                if let title = audiobook.title, !title.isEmpty {
                    Text(highlighted(title, query: query))
                        .font(.headline)
                        .foregroundColor(.primaryText)
                        .lineLimit(2)
                } else {
                    Text(NSLocalizedString("Unknown Title", comment: ""))
                        .font(.headline)
                        .foregroundColor(.primaryText)
                        .lineLimit(2)
                }

                if let author = audiobook.author, !author.isEmpty {
                    Text(highlighted(author, query: query))
                        .font(.subheadline)
                        .foregroundColor(.secondaryText)
                        .lineLimit(1)
                } else {
                    Text(NSLocalizedString("Unknown Author", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(percentageString)
                .font(.subheadline) // a little bigger than caption
                .fontWeight(.semibold)
                .foregroundColor(.secondaryText)
                .monospacedDigit()
                .accessibilityLabel(accessibilityProgress)
        }
        .padding(.vertical, 6)
    }

    private var cover: some View {
        Group {
            if let data = audiobook.coverImageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.secondaryBackground)
                    Image(systemName: "book.closed")
                        .foregroundColor(.secondaryText)
                }
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var percent: Double {
        guard audiobook.duration > 0 else { return 0 }
        return min(max(audiobook.currentPosition / audiobook.duration, 0), 1)
    }

    private var percentageString: String {
        "\(Int(percent * 100))%"
    }

    private var accessibilityProgress: String {
        let elapsed = audiobook.currentPosition
        let total = audiobook.duration
        func fmt(_ t: TimeInterval) -> String {
            let h = Int(t) / 3600
            let m = (Int(t) % 3600) / 60
            if h > 0 { return "\(h)h \(m)m" } else { return "\(m)m" }
        }
        return "\(percentageString), \(fmt(elapsed)) of \(fmt(total))"
    }

    private func highlighted(_ text: String, query: String) -> AttributedString {
        var attr = AttributedString(text)
        let ltext = text.lowercased()
        let lq = query.lowercased()
        if let r = ltext.range(of: lq),
           let lower = AttributedString.Index(r.lowerBound, within: attr),
           let upper = AttributedString.Index(r.upperBound, within: attr) {
            attr[lower..<upper].foregroundColor = .accentColor
            attr[lower..<upper].font = .headline.bold()
        }
        return attr
    }
}

// MARK: - Facets & Sorts
private enum Filter: CaseIterable { case all, inProgress, completed, notStarted
    var label: String {
        switch self {
        case .all: return NSLocalizedString("All", comment: "")
        case .inProgress: return NSLocalizedString("In Progress", comment: "")
        case .completed: return NSLocalizedString("Completed", comment: "")
        case .notStarted: return NSLocalizedString("Not Started", comment: "")
        }
    }
}

private enum Sort: CaseIterable { case relevance, recent, title, author, progress
    var label: String {
        switch self {
        case .relevance: return NSLocalizedString("Relevance", comment: "")
        case .recent: return NSLocalizedString("Recently Played", comment: "")
        case .title: return NSLocalizedString("Title", comment: "")
        case .author: return NSLocalizedString("Author", comment: "")
        case .progress: return NSLocalizedString("Progress", comment: "")
        }
    }
}

private struct EmptyPromptView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondaryText)
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primaryText)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primaryBackground)
    }
}

// Same visuals as EmptyPromptView, but suitable for inside List
private struct EmptyRowView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundColor(.secondaryText)
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primaryText)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
        .background(Color.clear)
    }
}
