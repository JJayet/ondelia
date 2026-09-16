import Foundation

/// A badge and the number that earns it. Progress is a pure function of the log — nothing is
/// stored except which badges have already been shown as unlocked.
struct Milestone: Identifiable, Hashable {
    enum Kind: Hashable {
        case books, streakDays, hours
        /// Ten hours started after 21:00.
        case nightOwl
        /// Ten hours started before 08:00.
        case earlyBird
    }

    let id: String
    let kind: Kind
    let target: Int
    let title: String
    let symbol: String

    static let all: [Milestone] = [
        Milestone(id: "books.1", kind: .books, target: 1, title: String(localized: "First Finish"), symbol: "checkmark.seal.fill"),
        Milestone(id: "books.10", kind: .books, target: 10, title: String(localized: "Bookworm"), symbol: "book.fill"),
        Milestone(id: "books.25", kind: .books, target: 25, title: String(localized: "Bibliophile"), symbol: "books.vertical.fill"),
        Milestone(id: "books.100", kind: .books, target: 100, title: String(localized: "Century Reader"), symbol: "building.columns.fill"),
        Milestone(id: "streak.7", kind: .streakDays, target: 7, title: String(localized: "Week Warrior"), symbol: "flame.fill"),
        Milestone(id: "streak.30", kind: .streakDays, target: 30, title: String(localized: "Month of Days"), symbol: "flame.fill"),
        Milestone(id: "streak.100", kind: .streakDays, target: 100, title: String(localized: "Hundred Days"), symbol: "flame.fill"),
        Milestone(id: "hours.100", kind: .hours, target: 100, title: String(localized: "100 Hours"), symbol: "headphones"),
        Milestone(id: "hours.500", kind: .hours, target: 500, title: String(localized: "500 Hours"), symbol: "headphones"),
        Milestone(id: "hours.1000", kind: .hours, target: 1000, title: String(localized: "1000 Hours"), symbol: "headphones"),
        Milestone(id: "nightOwl", kind: .nightOwl, target: 10, title: String(localized: "Night Owl"), symbol: "moon.stars.fill"),
        Milestone(id: "earlyBird", kind: .earlyBird, target: 10, title: String(localized: "Early Bird"), symbol: "sunrise.fill")
    ]

    /// Where the listener stands, in the badge's own unit (books, days, hours).
    func progress(in stats: ListeningStats, legacyHours: Int = 0, legacyBooks: Int = 0, legacyStreak: Int = 0) -> Int {
        switch kind {
        case .books: return stats.booksCompleted + legacyBooks
        case .streakDays: return max(stats.longestStreak, legacyStreak)
        case .hours: return Int(stats.totalSeconds / 3600) + legacyHours
        case .nightOwl:
            let buckets = stats.secondsByTimeOfDay
            return Int(((buckets[.lateNight] ?? 0) + (buckets[.night] ?? 0)) / 3600)
        case .earlyBird:
            return Int(stats.sessions.filter { stats.calendar.component(.hour, from: $0.startedAt) < 8 }
                .reduce(0) { $0 + $1.seconds } / 3600)
        }
    }
}
