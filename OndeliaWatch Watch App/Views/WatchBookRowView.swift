import SwiftUI

/// One row of the "In progress" list: cover, title, where the audio is, and the one action
/// that makes sense right now — play it, or ask the phone for it.
struct WatchBookRowView: View {
    let book: AudiobookModel

    private var transfers: WatchTransferState { .shared }
    private var sync: PhoneSyncService { .shared }

    private var chapterNumber: Int? { book.currentChapterNumber }

    private var chapterState: ChapterTransferState {
        guard let chapterNumber else { return .missing }
        return transfers.state(bookID: book.id, chapter: chapterNumber)
    }

    var body: some View {
        HStack(spacing: 8) {
            WatchCoverView(data: book.coverImageData)
            VStack(alignment: .leading, spacing: 2) {
                Text(book.displayTitle)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                status
            }
            Spacer(minLength: 0)
            action
        }
        .padding(.vertical, 2)
    }

    // MARK: - Status line

    @ViewBuilder
    private var status: some View {
        HStack(spacing: 4) {
            if hasContent {
                Circle().fill(.green).frame(width: 5, height: 5)
            }
            Text(statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var hasContent: Bool {
        !transfers.readyChapters(bookID: book.id).isEmpty
    }

    private var statusText: String {
        if hasContent { return String(localized: "On the watch") }
        if let fraction = transfers.incomingFraction(bookID: book.id) {
            return "\(Int((fraction * 100).rounded())) % · \(String(localized: "receiving"))"
        }
        if case .queued = chapterState { return String(localized: "waiting") }
        let percent = Int((book.progressFraction * 100).rounded())
        if streamsHere { return "\(percent) % · \(String(localized: "on server"))" }
        return "\(percent) % · \(String(localized: "on iPhone"))"
    }

    // MARK: - Action

    @ViewBuilder
    private var action: some View {
        Button {
            act()
        } label: {
            Image(systemName: actionIcon)
                .font(.system(size: 15, weight: .semibold))
        }
        .buttonStyle(.borderless)
        .buttonBorderShape(.circle)
        .frame(width: 34, height: 34)
        .background(.quaternary, in: Circle())
    }

    /// Away from the phone, a linked book plays from the server instead of waiting for files.
    private var streamsHere: Bool {
        !sync.isReachable && WatchServerAccount.shared.canStream(book)
    }

    private var actionIcon: String {
        chapterState.isReady || sync.isReachable || streamsHere ? "play.fill" : "arrow.down"
    }

    private func act() {
        if chapterState.isReady || streamsHere {
            Task { await WatchAudioManager.shared.loadAndPlay(book) }
            return
        }
        if sync.isReachable {
            sync.send(RemoteCommand.play(bookID: book.id))
            return
        }
        guard let chapterNumber else { return }
        sync.requestChapter(bookID: book.id, number: chapterNumber)
    }
}
