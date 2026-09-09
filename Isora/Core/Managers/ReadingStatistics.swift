import Foundation
import SwiftData

/// The listening log and the numbers read straight off it. Sessions are appended while a
/// book plays (phone or watch) and never touched again; the cards compute from them.
@MainActor
@Observable
final class ReadingStatistics {
    static let shared = ReadingStatistics()
    private let store: SwiftDataController

    private(set) var sessions: [ListeningSessionModel] = []
    var monthlyGoal: TimeInterval = 3600 * 10
    /// Just crossed a badge's line; the tab view shows it and clears it.
    var newlyUnlocked: Milestone?

    /// Hours, books and streak counted before the log existed. Per device, never synced; the
    /// log starts from zero on top of them so nobody's total drops on update.
    private(set) var legacyListeningTime: TimeInterval = 0
    private(set) var legacyBooksCompleted: Int = 0
    private(set) var legacyLongestStreak: Int = 0

    /// A pause under this long keeps the same session going.
    private static let sessionGap: TimeInterval = 120
    private var openSession: ListeningSessionModel?
    private var lastTickAt: Date = .distantPast

    init(store: SwiftDataController = .shared) {
        self.store = store
        let defaults = UserDefaults.standard
        monthlyGoal = defaults.double(forKey: "monthlyGoal")
        if monthlyGoal == 0 { monthlyGoal = 3600 * 10 }
        legacyListeningTime = defaults.double(forKey: "totalListeningTime")
        legacyBooksCompleted = defaults.integer(forKey: "booksCompleted")
        legacyLongestStreak = defaults.integer(forKey: "longestStreak")
        Task { await store.whenLoaded(); reload() }
    }

    /// Fetches the log. Also called after CloudKit merges another device's sessions.
    func reload() {
        guard store.isLoaded else { return }
        sessions = (try? store.context.fetch(FetchDescriptor<ListeningSessionModel>())) ?? []
        if UserDefaults.standard.array(forKey: "shownMilestones") == nil {
            // First run with badges: what is already earned is not news.
            UserDefaults.standard.set(unlockedMilestones.map(\.id), forKey: "shownMilestones")
        }
    }

    // MARK: - Writing

    /// `seconds` of wall-clock listening to `book`, ending at `at`. Speed is irrelevant here:
    /// two hours at 2× is two hours.
    func addListeningTime(_ seconds: TimeInterval, for book: AudiobookModel, at: Date = Date()) {
        guard store.isLoaded, seconds > 0 else { return }
        if let openSession, openSession.bookID == book.id, at.timeIntervalSince(lastTickAt) < Self.sessionGap {
            openSession.seconds += seconds
        } else {
            let session = ListeningSessionModel(book: book, startedAt: at.addingTimeInterval(-seconds), seconds: seconds)
            store.context.insert(session)
            sessions.append(session)
            openSession = session
        }
        lastTickAt = at
        checkMilestones()
    }

    /// The book just went from unfinished to finished. Rides on the open session when one is
    /// running, otherwise leaves a zero-second marker so the completion outlives the book.
    func recordFinish(_ book: AudiobookModel) {
        guard store.isLoaded else { return }
        if let openSession, openSession.bookID == book.id, !openSession.finishedBook {
            openSession.finishedBook = true
        } else {
            let marker = ListeningSessionModel(book: book, finishedBook: true)
            store.context.insert(marker)
            sessions.append(marker)
        }
        store.save()
        checkMilestones()
    }

    func updateMonthlyGoal(_ newGoal: TimeInterval) {
        monthlyGoal = newGoal
        UserDefaults.standard.set(newGoal, forKey: "monthlyGoal")
    }

    /// Clears the log and the pre-log counters. The goal stays.
    func resetAll() {
        for session in sessions { store.context.delete(session) }
        sessions = []
        openSession = nil
        legacyListeningTime = 0
        legacyBooksCompleted = 0
        legacyLongestStreak = 0
        for key in ["totalListeningTime", "booksCompleted", "longestStreak", "currentStreak", "monthlyProgress", "lastListenDate"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.set([String](), forKey: "shownMilestones")
        store.save()
    }

    // MARK: - Reading

    var stats: ListeningStats { ListeningStats(sessions) }

    var totalListeningTime: TimeInterval { legacyListeningTime + stats.totalSeconds }
    var booksCompleted: Int { legacyBooksCompleted + stats.booksCompleted }
    var currentStreak: Int { stats.currentStreak }
    var longestStreak: Int { max(legacyLongestStreak, stats.longestStreak) }
    var monthlyProgress: TimeInterval { stats.thisMonth }

    var monthlyGoalProgress: Double {
        guard monthlyGoal > 0 else { return 0 }
        return min(monthlyProgress / monthlyGoal, 1.0)
    }

    var formattedTotalTime: String { totalListeningTime.hoursMinutesFormatted }
    var formattedMonthlyProgress: String { monthlyProgress.hoursMinutesFormatted }
    var formattedMonthlyGoal: String { monthlyGoal.hoursMinutesFormatted }

    // MARK: - Milestones

    func progress(of milestone: Milestone, in stats: ListeningStats? = nil) -> Int {
        milestone.progress(
            in: stats ?? self.stats,
            legacyHours: Int(legacyListeningTime / 3600),
            legacyBooks: legacyBooksCompleted,
            legacyStreak: legacyLongestStreak
        )
    }

    var unlockedMilestones: [Milestone] {
        let stats = self.stats
        return Milestone.all.filter { progress(of: $0, in: stats) >= $0.target }
    }

    private func checkMilestones() {
        var shown = Set(UserDefaults.standard.stringArray(forKey: "shownMilestones") ?? [])
        guard let fresh = unlockedMilestones.first(where: { !shown.contains($0.id) }) else { return }
        shown.insert(fresh.id)
        UserDefaults.standard.set(Array(shown), forKey: "shownMilestones")
        newlyUnlocked = fresh
    }
}
