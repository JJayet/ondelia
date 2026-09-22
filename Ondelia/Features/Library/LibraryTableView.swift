import SwiftUI

/// One line of the table: a collection (with its books as children) or a book.
struct LibraryTableRow: Identifiable {
    let id: String
    let title: String
    let author: String
    let collectionName: String
    /// 0…1; shown as "—" when nothing has been heard.
    let progress: Double
    let duration: TimeInterval
    let isLocal: Bool
    let book: AudiobookModel?
    let group: CollectionGroup?
    var children: [LibraryTableRow] = []
}

/// The Mac-style library: sortable columns, collections folded like Finder folders. Offered in
/// regular width only; the phone renders the same mode as the list.
struct LibraryTableView: View {
    let groups: [CollectionGroup]
    let uncollected: [AudiobookModel]
    let onOpenBook: (AudiobookModel) -> Void
    let onOpenCollection: (CollectionGroup) -> Void

    @State private var sortOrder = [KeyPathComparator(\LibraryTableRow.title)]
    @State private var selection: LibraryTableRow.ID?
    /// Folders start open, as in the design; only the ones the user closes are remembered.
    @State private var collapsed: Set<LibraryTableRow.ID> = []

    var body: some View {
        Table(of: LibraryTableRow.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn(Text(NSLocalizedString("Title", comment: "Sort by title")), value: \.title) { row in
                titleCell(row)
            }
            TableColumn(Text(NSLocalizedString("Author", comment: "Sort by author")), value: \.author) { row in
                Text(row.author).foregroundStyle(.secondary)
            }
            TableColumn(Text(NSLocalizedString("Collection", comment: "Table column: collection")), value: \.collectionName) { row in
                Text(row.collectionName.isEmpty ? "—" : row.collectionName).foregroundStyle(.secondary)
            }
            TableColumn(Text(NSLocalizedString("Progress", comment: "Sort by progress")), value: \.progress) { row in
                Text(row.progress > 0 ? "\(Int(row.progress * 100)) %" : "—").monospacedDigit()
            }
            .width(min: 80, ideal: 100)
            TableColumn(Text(NSLocalizedString("Duration", comment: "Table column: duration")), value: \.duration) { row in
                Text(row.duration.hoursMinutesFormatted).monospacedDigit()
            }
            .width(min: 80, ideal: 100)
            TableColumn(Text(NSLocalizedString("Local", comment: "Table column: file is downloaded"))) { row in
                if row.book != nil {
                    Image(systemName: row.isLocal ? "checkmark.circle.fill" : "icloud.and.arrow.down")
                        .foregroundStyle(row.isLocal ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                }
            }
            .width(60)
            TableColumn(Text(verbatim: "Hardcover")) { row in
                if row.book?.hardcover != nil { HardcoverLinkMark(size: 12) }
            }
            .width(80)
        } rows: {
            ForEach(rows) { group in
                DisclosureTableRow(group, isExpanded: expanded(group.id)) {
                    ForEach(group.children) { TableRow($0) }
                }
            }
        }
        .tableStyle(.inset)
        .scrollContentBackground(.hidden)
        // Selection is the click: open what was picked and clear it, so a second click works.
        .onChange(of: selection) { _, id in
            guard let id else { return }
            selection = nil
            let all = rows.flatMap { [$0] + $0.children }
            guard let row = all.first(where: { $0.id == id }) else { return }
            if let book = row.book { onOpenBook(book) } else if let group = row.group { onOpenCollection(group) }
        }
    }

    private func expanded(_ id: LibraryTableRow.ID) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(id) },
            set: { open in if open { collapsed.remove(id) } else { collapsed.insert(id) } }
        )
    }

    /// Collections in shelf order, each with its books sorted by the column; the loose books
    /// last, under one folder of their own.
    private var rows: [LibraryTableRow] {
        var rows = groups.map { group in
            LibraryTableRow(
                id: group.id.uuidString,
                title: group.name,
                author: group.author ?? "",
                collectionName: "",
                progress: group.progressFraction,
                duration: group.totalDuration,
                isLocal: false,
                book: nil,
                group: group,
                children: group.books.map { row(for: $0, in: group.name) }.sorted(using: sortOrder)
            )
        }
        if !uncollected.isEmpty {
            rows.append(LibraryTableRow(
                id: "uncollected",
                title: NSLocalizedString("Other books", comment: "Table group: books in no collection"),
                author: "",
                collectionName: "",
                progress: 0,
                duration: uncollected.reduce(0) { $0 + $1.duration },
                isLocal: false,
                book: nil,
                group: nil,
                children: uncollected.map { row(for: $0, in: "") }.sorted(using: sortOrder)
            ))
        }
        return rows
    }

    private func row(for book: AudiobookModel, in collectionName: String) -> LibraryTableRow {
        LibraryTableRow(
            id: book.id.uuidString,
            title: book.title ?? AudiobookModel.unknownTitle,
            author: book.author ?? "",
            collectionName: collectionName,
            progress: book.progressFraction,
            duration: book.duration,
            isLocal: AudiobookManager.shared.hasFile(book),
            book: book,
            group: nil
        )
    }

    @ViewBuilder
    private func titleCell(_ row: LibraryTableRow) -> some View {
        HStack(spacing: 10) {
            if let book = row.book {
                CoverArtView(audiobook: book, size: 28, cornerRadius: 6)
                Text(row.title).lineLimit(1)
            } else {
                Text(row.title).fontWeight(.semibold).lineLimit(1)
                if let group = row.group {
                    Text(group.countLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
