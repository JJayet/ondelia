import Foundation

/// Everything the statistics screen shows, derived from the listening log. Pure: given the
/// same sessions, clock and calendar, the same numbers — so it is what the tests exercise.
struct ListeningStats {
    let sessions: [ListeningSessionModel]
    var now: Date = Date()
    var calendar: Calendar = .current

    init(_ sessions: [ListeningSessionModel], now: Date = Date(), calendar: Calendar = .current) {
        self.sessions = sessions
        self.now = now
        self.calendar = calendar
    }

    // MARK: - Totals

    var totalSeconds: TimeInterval { sessions.reduce(0) { $0 + $1.seconds } }

    func seconds(in interval: DateInterval) -> TimeInterval {
        sessions.filter { interval.contains($0.startedAt) }.reduce(0) { $0 + $1.seconds }
    }

    func seconds(inThe component: Calendar.Component, offset: Int = 0) -> TimeInterval {
        guard let anchor = calendar.date(byAdding: component, value: offset, to: now),
              let interval = calendar.dateInterval(of: component, for: anchor) else { return 0 }
        return seconds(in: interval)
    }

    var thisWeek: TimeInterval { seconds(inThe: .weekOfYear) }
    var lastWeek: TimeInterval { seconds(inThe: .weekOfYear, offset: -1) }
    var thisMonth: TimeInterval { seconds(inThe: .month) }
    var thisYear: TimeInterval { seconds(inThe: .year) }

    /// Only sessions with real time in them: a "marked finished" row is not a session.
    private var timedSessions: [ListeningSessionModel] { sessions.filter { $0.seconds > 0 } }

    var averageSession: TimeInterval {
        let timed = timedSessions
        guard !timed.isEmpty else { return 0 }
        return timed.reduce(0) { $0 + $1.seconds } / Double(timed.count)
    }

    var longestSession: TimeInterval { timedSessions.map(\.seconds).max() ?? 0 }

    // MARK: - Days and streaks

    /// Seconds per calendar day, keyed by the start of that day.
    var secondsByDay: [Date: TimeInterval] {
        timedSessions.reduce(into: [:]) { days, session in
            days[calendar.startOfDay(for: session.startedAt), default: 0] += session.seconds
        }
    }

    var activeDays: Set<Date> { Set(secondsByDay.keys) }

    /// Consecutive days ending today, or ending yesterday: a streak is not broken until the day
    /// with nothing in it is over.
    var currentStreak: Int {
        let days = activeDays
        var day = calendar.startOfDay(for: now)
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day), days.contains(yesterday) else {
                return 0
            }
            day = yesterday
        }
        var streak = 0
        while days.contains(day), let previous = calendar.date(byAdding: .day, value: -1, to: day) {
            streak += 1
            day = previous
        }
        return streak
    }

    var longestStreak: Int {
        let days = activeDays.sorted()
        var best = 0, run = 0
        var previous: Date?
        for day in days {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }

    /// `weeks` columns of seven days, oldest first, ending on today. Missing days are zero.
    func heatmap(weeks: Int) -> [[TimeInterval]] {
        let byDay = secondsByDay
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today) - calendar.firstWeekday
        let daysIntoWeek = (weekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -(weeks - 1) * 7 - daysIntoWeek, to: today) else {
            return []
        }
        return (0..<weeks).map { week in
            (0..<7).map { day in
                guard let date = calendar.date(byAdding: .day, value: week * 7 + day, to: start), date <= today else {
                    return -1
                }
                return byDay[date] ?? 0
            }
        }
    }

    // MARK: - Months

    var secondsByMonth: [Date: TimeInterval] {
        timedSessions.reduce(into: [:]) { months, session in
            guard let month = calendar.dateInterval(of: .month, for: session.startedAt)?.start else { return }
            months[month, default: 0] += session.seconds
        }
    }

    var bestMonth: (month: Date, seconds: TimeInterval)? {
        secondsByMonth.max { $0.value < $1.value }.map { ($0.key, $0.value) }
    }

    struct MonthMix: Identifiable {
        let month: Date
        /// Books listened to that month, most hours first.
        let books: [(title: String, seconds: TimeInterval)]
        var total: TimeInterval { books.reduce(0) { $0 + $1.seconds } }
        var id: Date { month }
    }

    /// One row per month of the year that had any listening, January first.
    func monthlyMix(ofYear year: Int) -> [MonthMix] {
        var byMonth: [Date: [UUID: (String, TimeInterval)]] = [:]
        for session in timedSessions where calendar.component(.year, from: session.startedAt) == year {
            guard let month = calendar.dateInterval(of: .month, for: session.startedAt)?.start else { continue }
            let current = byMonth[month, default: [:]][session.bookID]
            byMonth[month, default: [:]][session.bookID] = (session.title, (current?.1 ?? 0) + session.seconds)
        }
        return byMonth.keys.sorted().map { month in
            MonthMix(
                month: month,
                books: byMonth[month, default: [:]].values
                    .map { (title: $0.0, seconds: $0.1) }
                    .sorted { $0.seconds > $1.seconds }
            )
        }
    }

    // MARK: - Time of day

    enum TimeOfDay: Int, CaseIterable, Identifiable {
        case morning, afternoon, evening, lateNight, night
        var id: Int { rawValue }

        init(hour: Int) {
            switch hour {
            case 5..<12: self = .morning
            case 12..<17: self = .afternoon
            case 17..<21: self = .evening
            case 21..<24: self = .lateNight
            default: self = .night
            }
        }
    }

    var secondsByTimeOfDay: [TimeOfDay: TimeInterval] {
        timedSessions.reduce(into: [:]) { buckets, session in
            let hour = calendar.component(.hour, from: session.startedAt)
            buckets[TimeOfDay(hour: hour), default: 0] += session.seconds
        }
    }

    var favouriteTimeOfDay: TimeOfDay? {
        secondsByTimeOfDay.max { $0.value < $1.value }?.key
    }

    // MARK: - People and genres

    struct Ranked: Identifiable {
        let name: String
        let seconds: TimeInterval
        var id: String { name }
    }

    func top(_ key: (ListeningSessionModel) -> String?, limit: Int = 5) -> [Ranked] {
        let totals = timedSessions.reduce(into: [String: TimeInterval]()) { totals, session in
            guard let name = key(session)?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return }
            totals[name, default: 0] += session.seconds
        }
        return totals.map { Ranked(name: $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
            .prefix(limit)
            .map { $0 }
    }

    var topAuthors: [Ranked] { top(\.author) }
    var topNarrators: [Ranked] { top(\.narrator) }

    /// A book with three genres counts its hours under each of them.
    var genres: [Ranked] {
        let totals = timedSessions.reduce(into: [String: TimeInterval]()) { totals, session in
            for genre in session.genres { totals[genre, default: 0] += session.seconds }
        }
        return totals.map { Ranked(name: $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
            .prefix(6)
            .map { $0 }
    }
}
