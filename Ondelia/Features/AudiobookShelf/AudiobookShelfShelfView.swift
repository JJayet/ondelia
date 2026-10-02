import SwiftUI

/// Which shelf the Library screen shows.
enum LibrarySource: String {
    case device
    case audiobookShelf
}

/// The AudiobookShelf server as a library shelf: series, books (series folded) or authors,
/// loaded a page at a time as it scrolls, plus server-side search.
struct AudiobookShelfShelfView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case series, books, authors
        var id: Self { self }

        var title: String {
            switch self {
            // Its own key: "Series" is already the singular label ("Série"); the tab is plural.
            case .series: String(localized: "shelf.tab.series", defaultValue: "Series", comment: "AudiobookShelf shelf tab: series")
            case .books: NSLocalizedString("Books", comment: "AudiobookShelf shelf tab: books")
            case .authors: NSLocalizedString("Authors", comment: "AudiobookShelf shelf tab: authors")
            }
        }
    }

    private let service = AudiobookShelfService.shared
    @AppStorage("audiobookshelf.shelfTab") private var tab: Tab = .series
    @State private var libraries: [AudiobookShelfAPI.Library] = []
    @State private var library: String?
    @State private var shelves: AudiobookShelfShelves?
    @State private var error: String?
    @State private var query = ""
    @State private var results: AudiobookShelfAPI.SearchResults?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                controls
                if let error, shelves == nil {
                    ContentUnavailableView(
                        NSLocalizedString("Couldn't Load Library", comment: "AudiobookShelf load failure title"),
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if let results, !query.isEmpty {
                    AudiobookShelfSearchResultsView(results: results, query: query)
                } else if let shelves, let library {
                    AudiobookShelfTabContent(tab: tab, shelves: shelves, library: library)
                } else if libraries.isEmpty, shelves == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .serverSeriesDestinations(library: library ?? "")
        .task { await loadLibraries() }
        .task(id: query) { await search() }
        .onChange(of: library) { _, id in
            service.selectedLibrary = id
            shelves = id.map(AudiobookShelfShelves.init(library:))
        }
        .refreshable {
            shelves = library.map(AudiobookShelfShelves.init(library:))
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(
                    NSLocalizedString("Search the server", comment: "AudiobookShelf shelf search field"),
                    text: $query
                )
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(NSLocalizedString("Clear", comment: "Clear the search field"))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .glassEffect(in: .capsule)

            if query.isEmpty {
                HStack {
                    Picker(NSLocalizedString("Show", comment: "AudiobookShelf shelf tab picker"), selection: $tab) {
                        ForEach(Tab.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if libraries.count > 1 {
                        Menu {
                            Picker(NSLocalizedString("Library", comment: "AudiobookShelf library picker"), selection: $library) {
                                ForEach(libraries) { Text($0.name).tag(Optional($0.id)) }
                            }
                        } label: {
                            Image(systemName: "rectangle.stack")
                                .frame(width: 34, height: 34)
                                .glassEffect(.regular, in: Circle())
                        }
                        .accessibilityLabel(NSLocalizedString("Library", comment: "AudiobookShelf library picker"))
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private func loadLibraries() async {
        guard libraries.isEmpty, let server = service.server, let token = service.token else { return }
        do {
            libraries = try await AudiobookShelfAPI.libraries(server: server, token: token)
            let saved = service.selectedLibrary
            library = libraries.contains { $0.id == saved } ? saved : libraries.first?.id
            if library == nil {
                error = NSLocalizedString("This server has no book library.", comment: "AudiobookShelf: server has no book library")
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            results = nil
            return
        }
        // Debounce: `.task(id:)` cancels this sleep when the next keystroke arrives.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled, let library, let server = service.server, let token = service.token else { return }
        results = try? await AudiobookShelfAPI.search(server: server, token: token, library: library, query: text)
    }
}

/// The three pagers of one library, rebuilt when the library changes or on pull to refresh.
@MainActor
final class AudiobookShelfShelves {
    let books: AudiobookShelfPager<AudiobookShelfAPI.Item>
    let series: AudiobookShelfPager<AudiobookShelfAPI.Series>
    let authors: AudiobookShelfPager<AudiobookShelfAPI.Author>

    init(library: String) {
        func session() throws -> (URL, String) {
            let service = AudiobookShelfService.shared
            guard let server = service.server, let token = service.token else {
                throw AudiobookShelfAPI.Failure.http(401)
            }
            return (server, token)
        }
        books = AudiobookShelfPager { page in
            let (server, token) = try await MainActor.run { try session() }
            return try await AudiobookShelfAPI.items(
                server: server, token: token, library: library, page: page, collapseSeries: true
            )
        }
        series = AudiobookShelfPager { page in
            let (server, token) = try await MainActor.run { try session() }
            return try await AudiobookShelfAPI.series(server: server, token: token, library: library, page: page)
        }
        authors = AudiobookShelfPager { _ in
            let (server, token) = try await MainActor.run { try session() }
            let all = try await AudiobookShelfAPI.authors(server: server, token: token, library: library)
            return (all, all.count)
        }
    }
}
