import SwiftUI

/// The server audiobooks of the server library the phone has selected, by title, with search.
/// Tapping one opens the player; the book joins the Library when it is first opened.
struct WatchServerBrowseView: View {
    @State private var items: [AudiobookShelfAPI.Item] = []
    @State private var total: Int?
    @State private var query = ""
    /// Nil while not searching, so the paged list shows instead.
    @State private var results: [AudiobookShelfAPI.Item]?
    @State private var failure: String?
    @State private var opening: String?
    @State private var opened: AudiobookModel?

    private var account: WatchServerAccount { .shared }

    var body: some View {
        List {
            ForEach(results ?? items) { item in
                Button {
                    Task { await open(item) }
                } label: {
                    row(item)
                }
                .disabled(opening != nil)
                .onAppear {
                    guard results == nil, item.id == items.last?.id else { return }
                    Task { await loadPage() }
                }
            }
            if let failure {
                Text(failure)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(Text(String(localized: "Server")))
        .searchable(text: $query)
        .task { await loadPage() }
        .task(id: query) { await search() }
        .navigationDestination(item: $opened) { WatchPlayerView(book: $0) }
    }

    private func row(_ item: AudiobookShelfAPI.Item) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                if let author = item.author {
                    Text(author)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if opening == item.id { ProgressView().frame(width: 20) }
        }
    }

    // MARK: - Loading

    private func loadPage() async {
        guard let server = account.server, let token = account.token, let library = account.library,
              total.map({ items.count < $0 }) ?? true else { return }
        do {
            let page = items.count / AudiobookShelfAPI.pageSize
            let (more, count) = try await AudiobookShelfAPI.items(
                server: server, token: token, library: library, page: page
            )
            // Two rows appearing at once can ask for the same page.
            guard items.count / AudiobookShelfAPI.pageSize == page else { return }
            items += more
            total = more.isEmpty ? items.count : count
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            results = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled, let server = account.server, let token = account.token,
              let library = account.library else { return }
        do {
            results = try await AudiobookShelfAPI.search(
                server: server, token: token, library: library, query: text
            ).books
            failure = nil
        } catch {
            guard !Task.isCancelled else { return }
            failure = error.localizedDescription
        }
    }

    private func open(_ item: AudiobookShelfAPI.Item) async {
        opening = item.id
        defer { opening = nil }
        do {
            opened = try await account.join(item)
        } catch {
            failure = error.localizedDescription
        }
    }
}
