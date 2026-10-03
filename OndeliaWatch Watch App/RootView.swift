import SwiftData
import SwiftUI

/// The "In progress" list: at most three books, whichever the phone put first.
struct RootView: View {
    @Query(sort: \AudiobookModel.lastPlayed, order: .reverse)
    private var audiobooks: [AudiobookModel]

    private var sync: PhoneSyncService { .shared }

    private var books: [AudiobookModel] {
        Array(sync.orderedBooks(from: audiobooks).prefix(3))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text(String(localized: "In Progress")))
                .toolbar {
                    if WatchServerAccount.shared.canBrowse {
                        ToolbarItem(placement: .topBarLeading) {
                            NavigationLink {
                                WatchServerBrowseView()
                            } label: {
                                Label(String(localized: "Server"), systemImage: "server.rack")
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            OnWatchStorageView()
                        } label: {
                            Image(systemName: "internaldrive")
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if books.isEmpty {
            NothingOnWatchView(requestTitle: requestTitle, onRequest: requestCurrentChapter)
        } else {
            List {
                ForEach(books) { book in
                    NavigationLink {
                        WatchPlayerView(book: book)
                    } label: {
                        WatchBookRowView(book: book)
                    }
                }
                if let recent = books.first {
                    Section {
                        NavigationLink {
                            WatchChaptersView(book: recent)
                        } label: {
                            Label(String(localized: "Chapters"), systemImage: "list.bullet")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty state

    /// Only offered when the phone told us what it is playing — there is nothing else to ask for.
    private var requestTitle: String? {
        guard let pending = pendingRequest else { return nil }
        return String(localized: "Request ch. \(pending.1)")
    }

    private var pendingRequest: (UUID, Int)? {
        guard let nowPlaying = sync.phoneNowPlaying,
              let book = audiobooks.first(where: { $0.id == nowPlaying.bookID }),
              let chapter = book.chapter(at: nowPlaying.position) else { return nil }
        return (book.id, Int(chapter.chapterNumber))
    }

    private func requestCurrentChapter() {
        guard let pending = pendingRequest else { return }
        sync.requestChapter(bookID: pending.0, number: pending.1)
    }
}

#Preview {
    RootView()
        .modelContainer(for: AudiobookModel.self, inMemory: true)
}
