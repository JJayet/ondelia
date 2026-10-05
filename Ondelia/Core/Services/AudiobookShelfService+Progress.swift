import Foundation

/// Keeps a linked book's position in step with the server, so the web client and other apps
/// resume where this one stopped, and the other way round. Streamed and downloaded books alike:
/// what links them is the item, not where the audio comes from.
extension AudiobookShelfService {
    struct PushedProgress: Equatable {
        let position: TimeInterval
        let isFinished: Bool
    }

    /// How much book time must pass before the position is pushed again while playing.
    /// Progress is written locally every five seconds, which is not a rate to send to a server.
    nonisolated static let progressPushInterval: TimeInterval = 30

    /// Whether a local position write is worth a request.
    ///
    /// Always when it is the last word — a pause, a seek while paused, a finish — since nothing
    /// follows it; otherwise once the book has moved `progressPushInterval` on.
    nonisolated static func shouldPush(
        _ next: PushedProgress,
        lastPushed: PushedProgress?,
        isPlaying: Bool
    ) -> Bool {
        guard let lastPushed else { return true }
        // Marked read or unread: news even when the position did not move.
        if next.isFinished != lastPushed.isFinished { return true }
        let moved = abs(next.position - lastPushed.position)
        if moved < 1 { return false }
        if next.isFinished || !isPlaying { return true }
        return moved >= progressPushInterval
    }

    /// Pushes the book's position when it has moved enough. Called on every progress write.
    func pushProgress(for book: AudiobookModel) {
        guard let item = itemID(for: book), let (server, token) = session(forItem: item),
              book.duration > 0, !pushingProgress.contains(book.id) else { return }
        let position = min(max(book.currentPosition, 0), book.duration)
        let next = PushedProgress(position: position, isFinished: book.isFinished)
        guard position.isFinite, Self.shouldPush(
            next,
            lastPushed: pushedProgress[book.id],
            isPlaying: GlobalAudioManager.shared.isPlaying()
        ) else { return }

        pushingProgress.insert(book.id)
        // Recorded before the request, so a failing server is retried at the next interval
        // rather than on every five-second tick.
        pushedProgress[book.id] = next
        let (id, duration, isFinished) = (book.id, book.duration, book.isFinished)
        Task {
            do {
                try await AudiobookShelfAPI.updateProgress(
                    server: server, token: token, item: item,
                    currentTime: position, duration: duration, isFinished: isFinished
                )
            } catch {
                Log.library.error("AudiobookShelf: progress push failed: \(error.localizedDescription)")
            }
            pushingProgress.remove(id)
            // A write that came in while this one was in flight was turned away above. Paused,
            // or marked finished, there may be no later write to carry it, so it goes now.
            if !book.isDeleted, book.modelContext != nil { pushProgress(for: book) }
        }
    }

    /// Takes the server's position before the book opens, when it is the newer one. Bounded by
    /// a short timeout: an unreachable server must not hold up playback of a downloaded book.
    func pullProgress(for book: AudiobookModel) async {
        guard let item = itemID(for: book), let (server, token) = session(forItem: item) else { return }
        let remote: AudiobookShelfAPI.MediaProgress?
        do {
            remote = try await AudiobookShelfAPI.progress(server: server, token: token, item: item, timeout: 4)
        } catch {
            Log.library.error("AudiobookShelf: progress pull failed: \(error.localizedDescription)")
            return
        }
        guard let remote,
              ListenerState.shared.apply(.position(remote.currentTime), to: book, from: .server, at: remote.updatedAt)
        else { return }
        // ListenerState does not push a server change back to the server; this is what the
        // server holds now, so the next local write is throttled against it.
        pushedProgress[book.id] = PushedProgress(position: remote.currentTime, isFinished: remote.isFinished)
        if remote.isFinished != book.isFinished {
            ListenerState.shared.apply(remote.isFinished ? .finish : .unfinish, to: book, from: .server, at: remote.updatedAt)
        }
    }
}
