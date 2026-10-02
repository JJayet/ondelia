import Foundation

// MARK: - Completed books
extension ListeningStats {
    /// Two Finishes of one audiobook this close together are one completion recorded twice:
    /// two devices each logged it before CloudKit merged their logs.
    static let sameFinishWindow: TimeInterval = 24 * 3600

    /// Every Finish once, the earliest of each same-completion pair kept. The log itself stays
    /// append-only.
    var finishes: [ListeningSessionModel] {
        var kept: [ListeningSessionModel] = []
        for finish in sessions.filter(\.finishedBook).sorted(by: { $0.startedAt < $1.startedAt }) {
            let repeated = kept.contains {
                $0.bookID == finish.bookID && finish.startedAt.timeIntervalSince($0.startedAt) < Self.sameFinishWindow
            }
            if !repeated { kept.append(finish) }
        }
        return kept
    }

    var booksCompleted: Int { finishes.count }

    var completedThisYear: Int {
        let year = calendar.component(.year, from: now)
        return finishes.filter { calendar.component(.year, from: $0.startedAt) == year }.count
    }

    /// Time from the first session of each listen to the Finish that ended it, for every Finish
    /// with a timed session in its listen. A re-listen starts after the previous Finish of the
    /// same audiobook, so it is not measured from the first listen months earlier.
    var finishDurations: [TimeInterval] {
        let sessionsByBook = timedSessionsByBook
        var previousFinish: [UUID: Date] = [:]
        return finishes.compactMap { finish in
            defer { previousFinish[finish.bookID] = finish.startedAt }
            let after = previousFinish[finish.bookID] ?? .distantPast
            guard let first = sessionsByBook[finish.bookID]?.map(\.startedAt).filter({ $0 > after }).min()
            else { return nil }
            return max(finish.startedAt.timeIntervalSince(first), 0)
        }
    }

    var fastestFinish: TimeInterval? { finishDurations.min() }

    var averageFinish: TimeInterval? {
        let durations = finishDurations
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / Double(durations.count)
    }

    /// The narrator with the most finished books, and how many.
    var topNarratorByFinishes: (name: String, count: Int)? {
        let counts = finishes.reduce(into: [String: Int]()) { counts, finish in
            guard let narrator = finish.narrator, !narrator.isEmpty else { return }
            counts[narrator, default: 0] += 1
        }
        return counts.max { $0.value < $1.value }.map { ($0.key, $0.value) }
    }

    private var timedSessionsByBook: [UUID: [ListeningSessionModel]] {
        Dictionary(grouping: sessions.filter { $0.seconds > 0 }, by: \.bookID)
    }
}
