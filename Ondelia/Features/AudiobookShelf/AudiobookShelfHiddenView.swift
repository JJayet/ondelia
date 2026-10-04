import SwiftUI

/// One server's books, series and authors, each with a switch to show or hide it.
struct AudiobookShelfHiddenView: View {
    let account: AudiobookShelfAccount

    private struct Row: Identifiable {
        let id: String
        let name: String
        var detail: String?
    }

    @State private var kind = HiddenServerEntryModel.Kind.series
    @State private var query = ""
    @State private var hiddenOnly = false
    @State private var rows: [HiddenServerEntryModel.Kind: [Row]] = [:]
    @State private var error: String?
    private let hidden = AudiobookShelfHidden.shared

    /// Collections arrive with server collections.
    private static let kinds: [HiddenServerEntryModel.Kind] = [.series, .book, .author]

    var body: some View {
        List {
            Section {
                Picker(NSLocalizedString("Show", comment: "Hidden & Shown: which kind of entry is listed"), selection: $kind) {
                    ForEach(Self.kinds, id: \.self) { Text(Self.title(of: $0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                Toggle(NSLocalizedString("Hidden Only", comment: "Hidden & Shown: list only what is hidden"), isOn: $hiddenOnly)
            } footer: {
                if kind == .author {
                    Text(NSLocalizedString(
                        "Hiding an author also hides all of their books.",
                        comment: "Hidden & Shown footer for authors"
                    ))
                } else if let error {
                    Text(error).foregroundStyle(.red)
                }
            }

            Section {
                ForEach(shown) { row in toggle(for: row) }
            }
        }
        .overlay {
            if rows[kind] == nil && !hiddenOnly && error == nil {
                ProgressView()
            } else if shown.isEmpty {
                ContentUnavailableView(
                    NSLocalizedString("Nothing Hidden", comment: "Hidden & Shown: empty list"),
                    systemImage: "eye"
                )
            }
        }
        .searchable(text: $query)
        .task { await load() }
        .navigationTitle(NSLocalizedString("Hidden & Shown", comment: "AudiobookShelf settings: hide or show server entries"))
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(TintedBackground(intensity: 0.6))
    }

    /// The rows of the chosen kind matching the search; only hidden ones come from the records,
    /// so they list even when the server is out of reach.
    private var shown: [Row] {
        let all = hiddenOnly
            ? hidden.hidden(kind, on: account.id).map { Row(id: $0.key.entityID, name: $0.name) }
            : rows[kind] ?? []
        let text = query.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? all : all.filter { $0.name.localizedStandardContains(text) || ($0.detail?.localizedStandardContains(text) ?? false) }
    }

    @ViewBuilder
    private func toggle(for row: Row) -> some View {
        let byAuthor = kind == .book ? hidden.hidingAuthor(of: row.detail, on: account.id) : nil
        Toggle(isOn: Binding(
            get: { byAuthor == nil && !hidden.isHidden(kind, row.id, on: account.id) },
            set: { isShown in
                withHapticFeedback {
                    if isShown {
                        hidden.show(kind, row.id, on: account.id)
                    } else if kind == .series {
                        AudiobookManager.shared.hideServerSeries(row.id, name: row.name, on: account.id)
                    } else {
                        hidden.hide(kind, row.id, name: row.name, on: account.id)
                    }
                }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                if let byAuthor {
                    Text(String(format: NSLocalizedString("Hidden with %@", comment: "Hidden & Shown: a book hidden because its author is"), byAuthor))
                        .font(.caption).foregroundStyle(.secondary)
                } else if let detail = row.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .disabled(byAuthor != nil)
    }

    /// Books and series from the catalogue when it holds this server library, else the server.
    private func load() async {
        guard rows.isEmpty, let token = AudiobookShelfService.shared.token(for: account), let library = account.library else { return }
        let catalog = AudiobookShelfCatalog.shared
        let server = account.server
        do {
            var items = catalog.items
            var series = catalog.series
            if catalog.serverID != account.id || catalog.library != library || items.isEmpty {
                async let fetchedItems = AudiobookShelfAPI.allItems(server: server, token: token, library: library)
                async let fetchedSeries = AudiobookShelfAPI.allSeries(server: server, token: token, library: library)
                (items, series) = try await (fetchedItems, fetchedSeries)
            }
            let authors = try await AudiobookShelfAPI.authors(server: server, token: token, library: library)
            rows = [
                .book: items.map { Row(id: $0.id, name: $0.title, detail: $0.author) },
                .series: series.map { Row(id: $0.id, name: $0.name) },
                .author: authors.map { Row(id: $0.id, name: $0.name) }
            ]
        } catch {
            self.error = error.localizedDescription
            hiddenOnly = true
        }
    }

    private static func title(of kind: HiddenServerEntryModel.Kind) -> String {
        switch kind {
        case .book: NSLocalizedString("Books", comment: "AudiobookShelf shelf tab: books")
        case .series: String(localized: "shelf.tab.series", defaultValue: "Series", comment: "AudiobookShelf shelf tab: series")
        case .collection: NSLocalizedString("Collections", comment: "Section title for collections")
        case .author: NSLocalizedString("Authors", comment: "AudiobookShelf shelf tab: authors")
        }
    }
}
