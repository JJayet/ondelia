import SwiftUI

/// The Statistics tab: streak ring, badges, then one card per way of slicing the log.
struct StatisticsView: View {
    let statistics: ReadingStatistics
    /// The ring animates in from zero on appear, so opening the sheet reads as progress being
    /// counted up rather than a static gauge.
    @State private var ringProgress: Double = 0

    var body: some View {
        // Computed once per body: every card below slices the same sessions.
        let stats = statistics.stats
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    streakCard
                    MilestonesRowView(statistics: statistics, stats: stats)
                    snapshot(stats)
                    HeatmapCard(stats: stats)
                    TimeOfDayCard(stats: stats)
                    YearlyMixCard(stats: stats)
                    CompletedCard(stats: stats, legacyBooks: statistics.booksCompleted - stats.booksCompleted)
                    RankedListCard(title: NSLocalizedString("Top Authors", comment: "Statistics card"), symbol: "person.2", rows: stats.topAuthors)
                    RankedListCard(title: NSLocalizedString("Top Narrators", comment: "Statistics card"), symbol: "waveform", rows: stats.topNarrators)
                    RankedListCard(
                        title: NSLocalizedString("Genres", comment: "Statistics card"),
                        symbol: "sparkles",
                        rows: stats.genres,
                        empty: NSLocalizedString("Link books to Hardcover to see genres.", comment: "Statistics: genre card empty state")
                    )
                }
                .padding(16)
            }
            .background(TintedBackground(intensity: 0.7))
            .scrollContentBackground(.hidden)
            .navigationTitle(NSLocalizedString("Statistics", comment: "Statistics view title"))
            .navigationBarTitleDisplayMode(.large)
            .task {
                ringProgress = statistics.monthlyGoalProgress
            }
            // A tab stays alive while a book plays, so the ring has to follow the month.
            .onChange(of: statistics.monthlyGoalProgress) { _, progress in ringProgress = progress }
        }
    }

    private var streakCard: some View {
        VStack(spacing: 16) {
            ZStack {
                // The soft bloom behind the ring in the design.
                Circle()
                    .fill(.tint)
                    .blur(radius: 26)
                    .opacity(0.4)
                    .padding(18)

                StreakRing(
                    progress: ringProgress,
                    days: statistics.currentStreak,
                    lineWidth: 13,
                    numberSize: 54
                )
            }
            .frame(width: 184, height: 184)

            Text(
                String(
                    format: NSLocalizedString(
                        "Best streak: %d days. %@ of this month's goal.",
                        comment: "Streak card footnote"
                    ),
                    statistics.longestStreak,
                    (statistics.monthlyGoalProgress).formatted(.percent.precision(.fractionLength(0)))
                )
            )
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 250)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 18)
        .glassCard(cornerRadius: 30)
    }

    /// The six-tile grid: what happened this week and what the log looks like overall.
    private func snapshot(_ stats: ListeningStats) -> some View {
        let tiles: [(String, String, String)] = [
            (NSLocalizedString("Listened", comment: "Snapshot tile"), statistics.formattedTotalTime,
             String(format: NSLocalizedString("%@ this month · %@ goal", comment: "Snapshot: month against goal"),
                    statistics.formattedMonthlyProgress, statistics.formattedMonthlyGoal)),
            (NSLocalizedString("This Week", comment: "Snapshot tile"), stats.thisWeek.hoursMinutesFormatted, weekDelta(stats)),
            (NSLocalizedString("Best Month", comment: "Snapshot tile"),
             stats.bestMonth.map { $0.month.formatted(.dateTime.month(.abbreviated)) } ?? "—",
             stats.bestMonth.map { $0.seconds.hoursMinutesFormatted } ?? NSLocalizedString("No listening yet", comment: "Snapshot: empty")),
            (NSLocalizedString("Avg Session", comment: "Snapshot tile"), stats.averageSession.hoursMinutesFormatted,
             String(format: NSLocalizedString("Longest %@", comment: "Snapshot: longest session"), stats.longestSession.hoursMinutesFormatted)),
            (NSLocalizedString("Completed", comment: "Snapshot tile"), "\(statistics.booksCompleted)",
             String(format: NSLocalizedString("%d this year", comment: "Snapshot: books finished this year"), stats.completedThisYear)),
            (NSLocalizedString("Streak", comment: "Snapshot tile"),
             String(format: NSLocalizedString("%dd", comment: "Snapshot: streak in days, short"), statistics.currentStreak),
             String(format: NSLocalizedString("Best %dd", comment: "Snapshot: best streak in days"), statistics.longestStreak))
        ]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            ForEach(tiles, id: \.0) { tile in
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(tile.0)
                    Text(tile.1)
                        .font(.system(size: 26, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(tile.2)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .glassCard(cornerRadius: 24)
            }
        }
    }

    private func weekDelta(_ stats: ListeningStats) -> String {
        guard stats.lastWeek > 0 else {
            return NSLocalizedString("Nothing last week", comment: "Snapshot: no comparison")
        }
        let change = (stats.thisWeek - stats.lastWeek) / stats.lastWeek
        return String(
            format: NSLocalizedString("%@ vs last week", comment: "Snapshot: week over week change"),
            change.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always()))
        )
    }
}

#Preview("Statistics") {
    StatisticsView(statistics: ReadingStatistics(store: .preview))
}
