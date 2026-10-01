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

    /// Whether the server's position is newer than the one on the device. A local position
    /// with no timestamp predates position sync and loses.
    nonisolated static func serverIsNewer(_ remote: AudiobookShelfAPI.MediaProgress, than local: Date?) -> Bool {
        guard let local else { return true }
        // A second of slack: the two clocks are not the same clock.
        return remote.updatedAt > local.addingTimeInterval(1)
    }

    /// Pushes the book's position when it has moved enough. Called on every progress write.
    func pushProgress(for book: AudiobookModel) {
        guard isSignedIn, let server, let token, let item = itemID(for: book),
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
            defer { pushingProgress.remove(id) }
            do {
                try await AudiobookShelfAPI.updateProgress(
                    server: server, token: token, item: item,
                    currentTime: position, duration: duration, isFinished: isFinished
                )
            } catch {
                Log.library.error("AudiobookShelf: progress push failed: \(error.localizedDescription)")
            }
        }
    }

    /// Takes the server's position before the book opens, when it is the newer one. Bounded by
    /// a short timeout: an unreachable server must not hold up playback of a downloaded book.
    func pullProgress(for book: AudiobookModel) async {
        guard isSignedIn, let server, let token, let item = itemID(for: book) else { return }
        let remote: AudiobookShelfAPI.MediaProgress?
        do {
            remote = try await AudiobookShelfAPI.progress(server: server, token: token, item: item, timeout: 4)
        } catch {
            Log.library.error("AudiobookShelf: progress pull failed: \(error.localizedDescription)")
            return
        }
        guard let remote, Self.serverIsNewer(remote, than: book.positionUpdatedAt) else { return }

        book.currentPosition = remote.currentTime
        book.positionUpdatedAt = remote.updatedAt
        // Smart rewind measures the pause from `lastPlayed`: it was the server's listen that
        // stopped at this position, and a book never played here would otherwise count as
        // paused since forever and always get the longest rewind.
        book.lastPlayed = max(book.lastPlayed, remote.updatedAt)
        // Recorded first, so the writes below do not echo the server's own position back.
        pushedProgress[book.id] = PushedProgress(position: remote.currentTime, isFinished: remote.isFinished)
        if remote.isFinished, !book.isFinished {
            AudiobookManager.shared.markAsFinished(book)
        } else if !remote.isFinished, book.isFinished {
            AudiobookManager.shared.markAsUnread(book)
        }
        SwiftDataController.shared.save()
    }
}
