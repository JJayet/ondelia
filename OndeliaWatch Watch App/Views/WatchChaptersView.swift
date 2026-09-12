import SwiftUI

/// Every chapter of one book, with where its audio is. Tapping plays it, or asks for it.
struct WatchChaptersView: View {
    let book: AudiobookModel

    private var audio: WatchAudioManager { .shared }
    private var transfers: WatchTransferState { .shared }

    private var currentNumber: Int? {
        audio.currentBook?.id == book.id
            ? audio.currentChapter.map { Int($0.chapterNumber) }
            : book.currentChapterNumber
    }

    var body: some View {
        List(book.sortedChapters, id: \.id) { chapter in
            let number = Int(chapter.chapterNumber)
            Button {
                tap(number)
            } label: {
                row(chapter, number: number)
            }
            .listItemTint(number == currentNumber ? .accentColor.opacity(0.25) : nil)
        }
        .navigationTitle(Text(String(localized: "Chapters")))
    }

    private func row(_ chapter: ChapterModel, number: Int) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(chapter.title ?? "\(String(localized: "Ch.")) \(number)")
                    .font(.footnote)
                    .lineLimit(1)
                Text(max(chapter.endTime - chapter.startTime, 0).hoursMinutesFormatted)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            ChapterStateBadgeView(state: transfers.state(bookID: book.id, chapter: number))
        }
    }

    private func tap(_ number: Int) {
        guard transfers.state(bookID: book.id, chapter: number).isReady else {
            PhoneSyncService.shared.requestChapter(bookID: book.id, number: number)
            return
        }
        Task {
            await audio.load(book)
            audio.playChapter(number: number)
        }
    }
}

/// The dot or glyph that says where a chapter's audio is.
struct ChapterStateBadgeView: View {
    let state: ChapterTransferState

    var body: some View {
        switch state {
        case .ready:
            Circle().fill(.green).frame(width: 6, height: 6)
        case .receiving(let fraction):
            Text("\(Int((fraction * 100).rounded())) %")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .queued:
            Image(systemName: "hourglass")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .missing:
            Image(systemName: "iphone")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
