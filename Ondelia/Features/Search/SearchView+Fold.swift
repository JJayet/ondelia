import SwiftUI

// MARK: - Either side of the fold (design 12)
//
// iPhone Duo: the field, the filter as a list with its counts (four segments do not fit half a
// screen), the sort and the recent searches on the left; the answer on the right.
extension SearchView {
    /// Kept short: the left half lists these under the filter.
    static let recentLimit = 5

    var recents: [String] {
        recentSearches.split(separator: "\n").map(String.init)
    }

    /// The query that led to a tapped book, at the top of the recent searches.
    func rememberSearch() {
        let term = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        let others = recents.filter { $0.caseInsensitiveCompare(term) != .orderedSame }
        recentSearches = ([term] + others).prefix(Self.recentLimit).joined(separator: "\n")
    }

    var foldQuestion: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(NSLocalizedString("Search", comment: "Search view title"))
                    .font(.system(size: 34, weight: .bold))
                    .padding(.top, 18)

                field.padding(.top, 16)

                SectionLabel(NSLocalizedString("Filter", comment: "Search filter picker label"))
                    .padding(.top, 22)
                    .padding(.bottom, 8)
                filterList

                HStack {
                    Text(NSLocalizedString("Sort by", comment: "Search sort picker label"))
                    Spacer()
                    Picker(NSLocalizedString("Sort by", comment: "Search sort picker label"), selection: $sort) {
                        ForEach(SearchSort.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                }
                .padding(.leading, 18)
                .padding(.trailing, 6)
                .frame(minHeight: 52)
                .glassCard(cornerRadius: 22)
                .padding(.top, 14)

                if !recents.isEmpty {
                    SectionLabel(NSLocalizedString("Recent", comment: "Collections sort: in progress, then recently played"))
                        .padding(.top, 22)
                        .padding(.bottom, 4)
                    ForEach(recents, id: \.self) { term in
                        Button {
                            withHapticFeedback { query = term }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                                Text(term)
                                Spacer()
                                Image(systemName: "arrow.up.left").foregroundStyle(.tertiary)
                            }
                            .font(.system(size: 15))
                            .frame(height: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private var field: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(NSLocalizedString("Search", comment: "Search view title"), text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    withHapticFeedback { query = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("Clear", comment: "Clear filters short label"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .glassEffect(.regular, in: Capsule())
    }

    private var filterList: some View {
        VStack(spacing: 0) {
            ForEach(SearchFilter.allCases, id: \.self) { choice in
                Button {
                    withHapticFeedback { filter = choice }
                } label: {
                    HStack {
                        Text(choice.label)
                        Spacer()
                        Text(verbatim: "\(entries(for: choice).count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.tint)
                            .opacity(filter == choice ? 1 : 0)
                            .frame(width: 20)
                    }
                    .font(.system(size: 16))
                    .padding(.horizontal, 18)
                    .frame(height: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(filter == choice ? .isSelected : [])
                if choice != SearchFilter.allCases.last { Divider().padding(.leading, 18) }
            }
        }
        .glassCard(cornerRadius: 22)
    }

    // MARK: Answer

    @ViewBuilder
    var foldAnswer: some View {
        if debouncedQuery.isEmpty {
            // Centred in its half, not on the whole screen.
            emptyPrompt.frame(maxHeight: .infinity)
        } else {
            List {
                if results.isEmpty {
                    noResults
                } else {
                    Text(String(
                        format: NSLocalizedString("%d books · %d results", comment: "Search: books searched and how many matched"),
                        entries(for: filter).count,
                        results.count
                    ))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)

                    if let pickedAuthor {
                        Button {
                            withHapticFeedback { self.pickedAuthor = nil }
                        } label: {
                            Label(pickedAuthor, systemImage: "xmark.circle.fill")
                                .glassPill(height: 34, tinted: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(format: NSLocalizedString("Written by %@", comment: "Book detail: author credit"), pickedAuthor))
                        .accessibilityHint(NSLocalizedString("Clear", comment: "Clear filters short label"))
                        .listRowSeparator(.hidden)
                    } else if !matchedAuthors.isEmpty {
                        Section(NSLocalizedString("Authors", comment: "Search: authors section")) {
                            ForEach(matchedAuthors, id: \.name) { author in authorRow(author.name, books: author.books) }
                        }
                    }
                    Section(NSLocalizedString("Books", comment: "Collection detail: books section")) {
                        resultRows
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    /// "Peter Straub, Stephen King" is two authors, each with their own row.
    static func authorNames(_ credit: String) -> [String] {
        credit.split(whereSeparator: { ",;&".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Authors whose name holds the query, with how many results are theirs: they come first.
    private var matchedAuthors: [(name: String, books: Int)] {
        let q = normalize(debouncedQuery)
        let names = results.flatMap { Self.authorNames($0.author) }.filter { normalize($0).contains(q) }
        return Dictionary(grouping: names, by: { $0 })
            .map { (name: $0.key, books: $0.value.count) }
            .sorted { $0.books > $1.books }
    }

    /// Narrows the results to the author's books; the pill above them goes back.
    private func authorRow(_ name: String, books: Int) -> some View {
        Button {
            withHapticFeedback { pickedAuthor = name }
        } label: {
            HStack(spacing: 12) {
                Text(name.split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined())
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.quaternary, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.headline)
                    Text(String(format: NSLocalizedString("%d books", comment: "AudiobookShelf: number of books in a series or by an author"), books))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
