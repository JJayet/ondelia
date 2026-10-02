import SwiftUI

/// What plays after the current book, in order: the collection's next volume when one chains,
/// then the play queue. Rows can be dragged into a new order or swiped away; tapping one starts
/// it now.
struct PlayQueueView: View {
    /// The book a collection names as next, if any. Shown first and not reorderable: its place
    /// is decided by the collection, not the queue. A server series can name one that has not
    /// joined the Library; playing it streams it, which makes it join.
    let chained: LibraryEntry?
    let onPlay: (AudiobookModel) -> Void

    private let queue = PlayQueue.shared
    private let library = AudiobookManager.shared
    @Environment(\.dismiss) private var dismiss

    private var queued: [AudiobookModel] {
        queue.books(in: library.audiobooks).filter { $0.id != chained?.book?.id }
    }

    var body: some View {
        NavigationStack {
            List {
                if let chained {
                    Section(NSLocalizedString("From the collection", comment: "Play queue: book a collection plays next")) {
                        switch chained {
                        case .book(let book): row(book)
                        case .server(let item): serverRow(item)
                        }
                    }
                }

                Section(NSLocalizedString("Up Next", comment: "Section title for the play queue")) {
                    if queued.isEmpty {
                        Text(NSLocalizedString("Nothing queued", comment: "Play queue: empty state"))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(queued, id: \.id) { row($0) }
                        .onMove { queue.move(fromOffsets: $0, toOffset: $1) }
                        .onDelete { offsets in
                            for index in offsets { queue.remove(queued[index]) }
                        }
                }
            }
            .navigationTitle(NSLocalizedString("Play Queue", comment: "Play queue sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("Done", comment: "Done button")) { dismiss() }
                }
            }
        }
    }

    private func row(_ book: AudiobookModel) -> some View {
        Button {
            withHapticFeedback {
                onPlay(book)
                dismiss()
            }
        } label: {
            rowLabel(entry: .book(book)) { CoverArtView(audiobook: book, size: 44, cornerRadius: 8) }
        }
        .buttonStyle(.plain)
    }

    private func serverRow(_ item: AudiobookShelfAPI.Item) -> some View {
        Button {
            withHapticFeedback {
                AudiobookShelfService.shared.join(item) { onPlay($0) }
                dismiss()
            }
        } label: {
            rowLabel(entry: .server(item)) {
                AudiobookShelfCover(item: item.id, title: item.title, size: 44, cornerRadius: 8)
            }
        }
        .buttonStyle(.plain)
    }

    private func rowLabel(entry: LibraryEntry, @ViewBuilder cover: () -> some View) -> some View {
        HStack(spacing: 13) {
            cover()
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title.isEmpty ? AudiobookModel.unknownTitle : entry.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(
                    String(
                        format: NSLocalizedString("%@ · %@", comment: "Author and duration"),
                        entry.author.isEmpty ? AudiobookModel.unknownAuthor : entry.author,
                        entry.duration.hoursMinutesFormatted
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
    }
}
