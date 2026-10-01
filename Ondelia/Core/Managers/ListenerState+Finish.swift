import Foundation

// MARK: - Finish
extension ListenerState {
    /// The only writer of `isFinished = true`. The first flip is a Finish in the listening log,
    /// which keeps it even after the audiobook leaves the Library.
    func recordFinish(_ audiobook: AudiobookModel, from source: Source, at: Date) {
        guard !audiobook.isFinished else { return }
        audiobook.isFinished = true
        // AudiobookShelf also reports Finishes this listener made in Ondelia on another device,
        // and the pull can land before CloudKit delivers that device's log entry. A Finish of the
        // same audiobook that close by is that one, not a second.
        if source == .server, hasFinish(of: audiobook, near: at) { return }
        statistics.recordFinish(audiobook, at: at)
    }

    private func hasFinish(of audiobook: AudiobookModel, near date: Date) -> Bool {
        statistics.sessions.contains {
            $0.finishedBook && $0.bookID == audiobook.id
                && abs($0.startedAt.timeIntervalSince(date)) < ListeningStats.sameFinishWindow
        }
    }
}
