import Foundation
import SwiftData

/// The listening log and the numbers read straight off it. Sessions are appended while a
/// book plays (phone or watch) and never touched again; the cards compute from them.
@MainActor
@Observable
final class ReadingStatistics {
    static let shared = ReadingStatistics()

    enum Defaults {
        /// Synced by `SettingsSync`, which never lets a stale value overwrite one set elsewhere.
        static let monthlyGoal = "monthlyGoal"
        /// Ids of the earned milestones, merged across devices by `SettingsSync`.
        static let shownMilestones = "shownMilestones"
    }

    static let defaultMonthlyGoal: TimeInterval = 3600 * 10
    private let store: SwiftDataController

    private(set) var sessions: [ListeningSessionModel] = []
    var monthlyGoal: TimeInterval = defaultMonthlyGoal
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
        loadMonthlyGoal()
        legacyListeningTime = defaults.double(forKey: "totalListeningTime")
        legacyBooksCompleted = defaults.integer(forKey: "booksCompleted")
        legacyLongestStreak = defaults.integer(forKey: "longestStreak")
        Task { await store.whenLoaded(); reload() }
    }

    /// Fetches the log. Also called after CloudKit merges another device's sessions.
    func reload() {
        guard store.isLoaded else { return }
        sessions = (try? store.context.fetch(FetchDescriptor<ListeningSessionModel>())) ?? []
        if UserDefaults.standard.array(forKey: Defaults.shownMilestones) == nil {
            // First run with badges: what is already earned is not news.
            UserDefaults.standard.set(unlockedMilestones.map(\.id), forKey: Defaults.shownMilestones)
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
    func recordFinish(_ book: AudiobookModel, at: Date = Date()) {
        guard store.isLoaded else { return }
        if let openSession, openSession.bookID == book.id, !openSession.finishedBook {
            openSession.finishedBook = true
        } else {
            let marker = ListeningSessionModel(book: book, startedAt: at, finishedBook: true)
            store.context.insert(marker)
            sessions.append(marker)
        }
        store.save()
        checkMilestones()
    }

    /// Takes back the most recent Finish of `book`: unflags the session it rode on, or removes
    /// the zero-second marker, which held nothing else. Earned milestones stay earned.
    func retractFinish(_ book: AudiobookModel) {
        guard store.isLoaded,
              let latest = sessions.filter({ $0.finishedBook && $0.bookID == book.id })
                .max(by: { $0.startedAt < $1.startedAt })
        else { return }
        if latest.seconds > 0 {
            latest.finishedBook = false
        } else {
            sessions.removeAll { $0 === latest }
            store.context.delete(latest)
        }
        store.save()
    }

    /// Reads the goal from defaults, where `SettingsSync` mirrors it from the other devices.
    func loadMonthlyGoal(from defaults: UserDefaults = .standard) {
        let stored = defaults.double(forKey: Defaults.monthlyGoal)
        monthlyGoal = stored > 0 ? stored : Self.defaultMonthlyGoal
    }

    func updateMonthlyGoal(_ newGoal: TimeInterval) {
        monthlyGoal = newGoal
        UserDefaults.standard.set(newGoal, forKey: Defaults.monthlyGoal)
        SettingsSync.publish(Defaults.monthlyGoal)
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
        UserDefaults.standard.set([String](), forKey: Defaults.shownMilestones)
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

    /// Once shown as unlocked, a badge stays lit even if its rule or the log later counts less.
    func hasEarned(_ milestone: Milestone) -> Bool {
        UserDefaults.standard.stringArray(forKey: Defaults.shownMilestones)?.contains(milestone.id) ?? false
    }

    var unlockedMilestones: [Milestone] {
        let stats = self.stats
        return Milestone.all.filter { progress(of: $0, in: stats) >= $0.target }
    }

    private func checkMilestones() {
        var shown = Set(UserDefaults.standard.stringArray(forKey: Defaults.shownMilestones) ?? [])
        // Only the unearned badges cost a scan; the shown ones are skipped before any stats work.
        let stats = self.stats
        guard let fresh = Milestone.all.first(where: { !shown.contains($0.id) && progress(of: $0, in: stats) >= $0.target })
        else { return }
        shown.insert(fresh.id)
        UserDefaults.standard.set(Array(shown), forKey: Defaults.shownMilestones)
        newlyUnlocked = fresh
    }
}
