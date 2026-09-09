import Foundation

// MARK: - Completed books
extension ListeningStats {
    var finishes: [ListeningSessionModel] { sessions.filter(\.finishedBook) }

    var booksCompleted: Int { finishes.count }

    var completedThisYear: Int {
        let year = calendar.component(.year, from: now)
        return finishes.filter { calendar.component(.year, from: $0.startedAt) == year }.count
    }

    /// Days from a book's first session to the one that finished it, for every finished book
    /// that has at least one timed session.
    var finishDurations: [TimeInterval] {
        let firstSession = timedSessionsByBook.compactMapValues { $0.map(\.startedAt).min() }
        return finishes.compactMap { finish in
            guard let first = firstSession[finish.bookID] else { return nil }
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
