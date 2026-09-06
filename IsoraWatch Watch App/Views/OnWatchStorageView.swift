import SwiftData
import SwiftUI

/// What the watch actually holds, chapter by chapter, with the only two ways to get rid of it:
/// swipe one away, or clear the lot.
struct OnWatchStorageView: View {
    @Query private var audiobooks: [AudiobookModel]

    private var transfers: WatchTransferState { .shared }
    private var sync: PhoneSyncService { .shared }

    var body: some View {
        List {
            ForEach(booksWithContent, id: \.id) { book in
                Section(book.displayTitle) {
                    ForEach(entries(of: book), id: \.number) { entry in
                        row(book: book, entry: entry)
                            .swipeActions {
                                Button(String(localized: "Delete"), role: .destructive) {
                                    sync.deleteChapter(bookID: book.id, number: entry.number)
                                }
                            }
                    }
                }
            }
            Section {
                Button(role: .destructive) {
                    sync.clearAll()
                } label: {
                    Text("\(sync.bytesOnDisk().fileSizeFormatted) \(String(localized: "used · Clear"))")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(Text(String(localized: "On the watch")))
    }

    // MARK: - Rows

    private struct Entry {
        let number: Int
        let title: String
        let length: TimeInterval
        let state: ChapterTransferState
    }

    private var booksWithContent: [AudiobookModel] {
        audiobooks.filter { !entries(of: $0).isEmpty }
    }

    private func entries(of book: AudiobookModel) -> [Entry] {
        book.sortedChapters.compactMap { chapter in
            let number = Int(chapter.chapterNumber)
            let state = transfers.state(bookID: book.id, chapter: number)
            guard state != .missing else { return nil }
            return Entry(
                number: number,
                title: chapter.title ?? "\(String(localized: "Ch.")) \(number)",
                length: max(chapter.endTime - chapter.startTime, 0),
                state: state
            )
        }
    }

    private func row(book: AudiobookModel, entry: Entry) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.title) · \(entry.length.hoursMinutesFormatted)")
                    .font(.footnote)
                    .lineLimit(1)
                statusLine(entry)
            }
            Spacer(minLength: 0)
            if entry.state.isReady {
                Button {
                    Task {
                        await WatchAudioManager.shared.load(book)
                        WatchAudioManager.shared.playChapter(number: entry.number)
                    }
                } label: {
                    Image(systemName: "play.fill").font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func statusLine(_ entry: Entry) -> some View {
        switch entry.state {
        case .ready(let bytes):
            Text("\(String(localized: "ready")) · \(bytes.fileSizeFormatted)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .receiving(let fraction):
            VStack(alignment: .leading, spacing: 2) {
                ProgressView(value: fraction)
                Text("\(String(localized: "sending from iPhone")) · \(Int((fraction * 100).rounded())) %")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .queued, .missing:
            Text(String(localized: "waiting"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
