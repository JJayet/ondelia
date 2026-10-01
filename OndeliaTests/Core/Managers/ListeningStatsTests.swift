import Testing
import Foundation
@testable import Isora

@MainActor
struct ListeningStatsTests {
    let calendar = Calendar(identifier: .gregorian)
    /// A Wednesday at noon.
    let now = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 12))!

    func session(_ book: AudiobookModel, daysAgo: Int, hour: Int = 10, minutes: Double, finished: Bool = false) -> ListeningSessionModel {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        return ListeningSessionModel(book: book, startedAt: start, seconds: minutes * 60, finishedBook: finished)
    }

    @Test("Totals are wall-clock seconds, streaks count consecutive days")
    func totalsAndStreaks() {
        let book = AudiobookModel(title: "Dune", author: "Herbert", narrator: "Simon")
        let stats = ListeningStats([
            session(book, daysAgo: 0, minutes: 30),
            session(book, daysAgo: 1, minutes: 60),
            session(book, daysAgo: 2, minutes: 15),
            session(book, daysAgo: 5, minutes: 120),
            session(book, daysAgo: 6, minutes: 10),
            session(book, daysAgo: 7, minutes: 10),
            session(book, daysAgo: 8, minutes: 10)
        ], now: now, calendar: calendar)

        #expect(stats.totalSeconds == TimeInterval(255 * 60))
        #expect(stats.currentStreak == 3)
        #expect(stats.longestStreak == 4)
        #expect(stats.longestSession == TimeInterval(120 * 60))
        #expect(stats.averageSession == TimeInterval(255 * 60) / 7)
        #expect(stats.topAuthors.first?.name == "Herbert")
        #expect(stats.topNarrators.first?.seconds == TimeInterval(255 * 60))
    }

    @Test("A streak survives a day with nothing in it until that day is over")
    func streakAliveFromYesterday() {
        let book = AudiobookModel(title: "Dune")
        let stats = ListeningStats([session(book, daysAgo: 1, minutes: 5), session(book, daysAgo: 2, minutes: 5)],
                                   now: now, calendar: calendar)
        #expect(stats.currentStreak == 2)
        let gap = ListeningStats([session(book, daysAgo: 2, minutes: 5)], now: now, calendar: calendar)
        #expect(gap.currentStreak == 0)
    }

    @Test("Finishes count without a timed session, and finish duration spans first session to finish")
    func finishes() {
        let book = AudiobookModel(title: "Dune", narrator: "Simon")
        let other = AudiobookModel(title: "Emma", narrator: "Simon")
        let stats = ListeningStats([
            session(book, daysAgo: 4, minutes: 60),
            session(book, daysAgo: 1, minutes: 60, finished: true),
            session(other, daysAgo: 0, minutes: 0, finished: true)
        ], now: now, calendar: calendar)
        #expect(stats.booksCompleted == 2)
        #expect(stats.completedThisYear == 2)
        #expect(stats.fastestFinish == TimeInterval(3 * 86_400))
        #expect(stats.topNarratorByFinishes?.count == 2)
        // The zero-second marker is not a session.
        #expect(stats.averageSession == TimeInterval(3600))
    }

    @Test("Two Finishes of one audiobook within a day count once; a later re-listen counts again")
    func sameFinishCountsOnce() {
        let book = AudiobookModel(title: "Dune")
        let stats = ListeningStats([
            session(book, daysAgo: 30, minutes: 0, finished: true),
            session(book, daysAgo: 30, hour: 18, minutes: 0, finished: true),
            session(book, daysAgo: 1, minutes: 0, finished: true)
        ], now: now, calendar: calendar)
        #expect(stats.booksCompleted == 2)
    }

    @Test("Heatmap ends today, has 7 rows per week, and marks future days")
    func heatmap() {
        let book = AudiobookModel(title: "Dune")
        let stats = ListeningStats([session(book, daysAgo: 0, minutes: 10)], now: now, calendar: calendar)
        let grid = stats.heatmap(weeks: 12)
        #expect(grid.count == 12)
        #expect(grid.allSatisfy { $0.count == 7 })
        // Wednesday with Sunday as first weekday: index 3 is today, the rest of the week is future.
        #expect(grid.last?[3] == TimeInterval(600))
        #expect(grid.last?[4] == -1)
        #expect(grid.joined().filter { $0 > 0 }.count == 1)
    }

    @Test("Monthly mix ranks books within the month; genres and time of day bucket by session")
    func mixAndBuckets() {
        let dune = AudiobookModel(title: "Dune")
        dune.hardcover = HardcoverLink(id: 1, title: "Dune", author: "Herbert", genres: ["Science Fiction", "Classics"])
        let emma = AudiobookModel(title: "Emma")
        let stats = ListeningStats([
            session(dune, daysAgo: 0, hour: 22, minutes: 30),
            session(emma, daysAgo: 1, hour: 7, minutes: 90)
        ], now: now, calendar: calendar)
        let mix = stats.monthlyMix(ofYear: 2026)
        #expect(mix.count == 1)
        #expect(mix.first?.books.first?.title == "Emma")
        #expect(mix.first?.total == TimeInterval(120 * 60))
        #expect(stats.genres.map(\.name).sorted() == ["Classics", "Science Fiction"])
        #expect(stats.secondsByTimeOfDay[.lateNight] == TimeInterval(30 * 60))
        #expect(stats.secondsByTimeOfDay[.morning] == TimeInterval(90 * 60))
        #expect(stats.favouriteTimeOfDay == .morning)
    }

    @Test("Milestones read progress off the stats plus the pre-log counters")
    func milestones() {
        let book = AudiobookModel(title: "Dune")
        let stats = ListeningStats([session(book, daysAgo: 0, hour: 23, minutes: 660, finished: true)], now: now, calendar: calendar)
        let first = Milestone.all.first { $0.id == "books.1" }!
        let owl = Milestone.all.first { $0.id == "nightOwl" }!
        let hours = Milestone.all.first { $0.id == "hours.100" }!
        #expect(first.progress(in: stats) == 1)
        #expect(owl.progress(in: stats) == 11)
        #expect(hours.progress(in: stats, legacyHours: 95) == 106)
    }
}
