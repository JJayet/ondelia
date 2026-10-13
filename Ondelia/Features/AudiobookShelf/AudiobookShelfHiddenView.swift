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
    @Environment(\.isFoldSplit) private var isFoldSplit

    private static let kinds: [HiddenServerEntryModel.Kind] = [.series, .collection, .book, .author]

    var body: some View {
        FoldSplit {
            // iPhone Duo (design 15b): four segments cannot fit half a screen, so the kinds
            // become a list with their counts, beside the search and the filter.
            List {
                searchField
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                Section {
                    ForEach(Self.kinds, id: \.self) { kindRow($0) }
                } header: {
                    Text(NSLocalizedString("Show", comment: "Hidden & Shown: which kind of entry is listed"))
                }
                Section {
                    hiddenOnlyToggle
                } footer: {
                    footer
                }
            }
        } secondary: {
            List {
                Section {
                    entries
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        FoldPaneTitle(Self.title(of: kind))
                        if let all = rows[kind] {
                            Text(String(
                                format: NSLocalizedString("Hidden: %1$d of %2$d", comment: "Hidden & Shown: hidden entries of the listed kind, out of all"),
                                hidden.hidden(kind, on: account.id).count, all.count
                            ))
                            .textCase(nil)
                        }
                    }
                }
            }
            .overlay { status }
        } fallback: {
            List {
                Section {
                    Picker(NSLocalizedString("Show", comment: "Hidden & Shown: which kind of entry is listed"), selection: $kind) {
                        ForEach(Self.kinds, id: \.self) { Text(Self.title(of: $0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    hiddenOnlyToggle
                } footer: {
                    footer
                }

                Section { entries }
            }
            .overlay { status }
            .searchable(text: $query)
        }
        .task { await load() }
        .navigationTitle(NSLocalizedString("Hidden & Shown", comment: "AudiobookShelf settings: hide or show server entries"))
        .navigationBarTitleDisplayMode(isFoldSplit ? .large : .inline)
        .scrollContentBackground(.hidden)
        .background(TintedBackground(intensity: 0.6))
    }

    private var hiddenOnlyToggle: some View {
        Toggle(NSLocalizedString("Hidden Only", comment: "Hidden & Shown: list only what is hidden"), isOn: $hiddenOnly)
    }

    @ViewBuilder private var footer: some View {
        if let error {
            Text(error).foregroundStyle(.red)
        } else if kind == .author {
            Text(NSLocalizedString(
                "Hiding an author also hides all of their books.",
                comment: "Hidden & Shown footer for authors"
            ))
        } else if isFoldSplit {
            Text(NSLocalizedString(
                "A hidden entry stays on the server. It no longer appears in Library, Search or Collections.",
                comment: "Hidden & Shown footer beside the kinds"
            ))
        }
    }

    private var entries: some View {
        ForEach(shown) { row in toggle(for: row) }
    }

    @ViewBuilder private var status: some View {
        if rows[kind] == nil && !hiddenOnly && error == nil {
            ProgressView()
        } else if shown.isEmpty {
            ContentUnavailableView(
                NSLocalizedString("Nothing Hidden", comment: "Hidden & Shown: empty list"),
                systemImage: "eye"
            )
        }
    }

    /// The navigation bar's search drawer would run across the fold.
    private var searchField: some View {
        TextField(NSLocalizedString("Search", comment: "Search view title"), text: $query)
            .textFieldStyle(.plain)
            .padding(.leading, 34)
            .frame(height: 40)
            .overlay(alignment: .leading) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).padding(.leading, 13)
            }
            .glassEffect(.regular, in: Capsule())
            .padding(.vertical, 4)
    }

    private func kindRow(_ rowKind: HiddenServerEntryModel.Kind) -> some View {
        Button {
            withHapticFeedback { kind = rowKind }
        } label: {
            LabeledContent(Self.title(of: rowKind)) {
                if let count = rows[rowKind]?.count { Text(count, format: .number) }
            }
            .foregroundStyle(Color.primaryText)
        }
        .listRowBackground(kind == rowKind ? Color.accentColor.opacity(0.12) : nil)
        .accessibilityAddTraits(kind == rowKind ? .isSelected : [])
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
                    } else if kind == .series || kind == .collection {
                        let group = AudiobookShelfAPI.Series(id: row.id, name: row.name, isCollection: kind == .collection)
                        AudiobookManager.shared.hideServerGroup(group, on: account.id)
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
            // Hidden rows fade, so what still shows reads at a glance.
            .opacity(byAuthor == nil && !hidden.isHidden(kind, row.id, on: account.id) ? 1 : 0.5)
        }
        .disabled(byAuthor != nil)
    }

    /// Books and series from the catalogue when it holds this server library, else the server.
    private func load() async {
        guard rows.isEmpty, let token = AudiobookShelfService.shared.token(for: account), let library = account.library else { return }
        let catalog = AudiobookShelfCatalog.shared
        let server = account.server
        do {
            let part = catalog.parts[account.id]
            var items = part?.items ?? []
            var series = part?.series ?? []
            var collections = part?.collections ?? []
            if part?.library != library || items.isEmpty {
                async let fetchedItems = AudiobookShelfAPI.allItems(server: server, token: token, library: library)
                async let fetchedSeries = AudiobookShelfAPI.allSeries(server: server, token: token, library: library)
                async let fetchedCollections = try? AudiobookShelfAPI.collections(server: server, token: token, library: library)
                (items, series, collections) = try await (fetchedItems, fetchedSeries, fetchedCollections ?? [])
            }
            let authors = try await AudiobookShelfAPI.authors(server: server, token: token, library: library)
            rows = [
                .book: items.map { Row(id: $0.id, name: $0.title, detail: $0.author) },
                .series: series.map { Row(id: $0.id, name: $0.name) },
                .collection: collections.map { Row(id: $0.id, name: $0.name) },
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
