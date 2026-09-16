import SwiftUI

/// Card chrome shared by every statistics section: an icon, the uppercase label, optional
/// trailing detail, then whatever the section draws.
struct StatCard<Trailing: View, Content: View>: View {
    let symbol: String
    let title: String
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tint)
                SectionLabel(title)
                trailing
            }
            content
        }
        .padding(18)
        .glassCard()
    }
}

/// Twelve weeks of days, GitHub style. Shade follows the day's share of the busiest day.
struct HeatmapCard: View {
    let stats: ListeningStats
    private static let weeks = 12

    var body: some View {
        let grid = stats.heatmap(weeks: Self.weeks)
        let peak = grid.joined().max() ?? 0
        let active = grid.joined().filter { $0 > 0 }.count
        StatCard(symbol: "calendar", title: NSLocalizedString("Listening Heatmap", comment: "Statistics card")) {
            Spacer()
            Text(String(format: NSLocalizedString("%d active", comment: "Heatmap: active days count"), active))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        } content: {
            HStack(spacing: 4) {
                ForEach(Array(grid.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: 4) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, seconds in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(fill(seconds, peak: peak))
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
            .accessibilityLabel(
                String(format: NSLocalizedString("%d active days in the last %d weeks", comment: "Heatmap accessibility"), active, Self.weeks)
            )
        }
    }

    private func fill(_ seconds: TimeInterval, peak: TimeInterval) -> AnyShapeStyle {
        guard seconds >= 0 else { return AnyShapeStyle(.clear) }
        guard seconds > 0, peak > 0 else { return AnyShapeStyle(.quaternary) }
        return AnyShapeStyle(Color.accentColor.opacity(0.3 + 0.7 * min(seconds / peak, 1)))
    }
}

/// Five buckets of the day, as one stacked bar and a list.
struct TimeOfDayCard: View {
    let stats: ListeningStats

    var body: some View {
        let buckets = stats.secondsByTimeOfDay
        let total = buckets.values.reduce(0, +)
        StatCard(symbol: "clock", title: NSLocalizedString("Time of Day", comment: "Statistics card")) {
            Spacer()
            if let favourite = stats.favouriteTimeOfDay {
                Text(favourite.title).glassPill(height: 28, tinted: true)
            }
        } content: {
            if total > 0 {
                GeometryReader { geometry in
                    HStack(spacing: 2) {
                        ForEach(ListeningStats.TimeOfDay.allCases) { bucket in
                            let share = (buckets[bucket] ?? 0) / total
                            if share > 0 {
                                Capsule()
                                    .fill(Color.accentColor.opacity(1 - 0.16 * Double(bucket.rawValue)))
                                    .frame(width: max(geometry.size.width * share - 2, 4))
                            }
                        }
                    }
                }
                .frame(height: 10)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(ListeningStats.TimeOfDay.allCases) { bucket in
                    HStack {
                        Text(bucket.title)
                        Spacer()
                        Text((buckets[bucket] ?? 0).hoursMinutesFormatted).foregroundStyle(.secondary)
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }
}

extension ListeningStats.TimeOfDay {
    var title: String {
        switch self {
        case .morning: NSLocalizedString("Morning", comment: "Time of day: 5–12")
        case .afternoon: NSLocalizedString("Afternoon", comment: "Time of day: 12–17")
        case .evening: NSLocalizedString("Evening", comment: "Time of day: 17–21")
        case .lateNight: NSLocalizedString("Late Night", comment: "Time of day: 21–24")
        case .night: NSLocalizedString("Night", comment: "Time of day: 0–5")
        }
    }
}

/// Authors, narrators, genres: a numbered list with hours on the right.
struct RankedListCard: View {
    let title: String
    let symbol: String
    let rows: [ListeningStats.Ranked]
    var empty: String = NSLocalizedString("Nothing yet", comment: "Statistics: empty list")

    var body: some View {
        StatCard(symbol: symbol, title: title) { EmptyView() } content: {
            if rows.isEmpty {
                Text(empty).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 12) {
                    Text(verbatim: "\(index + 1)")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(.quaternary, in: Circle())
                    Text(row.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                    Spacer()
                    Text(row.seconds.hoursMinutesFormatted)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Finished books: counts, how long a book takes, and the narrator finished most often.
struct CompletedCard: View {
    let stats: ListeningStats
    /// Completions counted before the log existed, added to the all-time figure only.
    let legacyBooks: Int

    var body: some View {
        StatCard(symbol: "checkmark.seal", title: NSLocalizedString("Completed Audiobooks", comment: "Statistics card")) { EmptyView() } content: {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                figure("\(stats.completedThisYear)", NSLocalizedString("This Year", comment: "Completed: this year"))
                figure("\(stats.booksCompleted + legacyBooks)", NSLocalizedString("All Time", comment: "Completed: all time"))
                figure(stats.fastestFinish.map(days) ?? "—", NSLocalizedString("Fastest", comment: "Completed: fastest finish"))
                figure(stats.averageFinish.map(days) ?? "—", NSLocalizedString("Avg Finish", comment: "Completed: average finish"))
            }
            if let top = stats.topNarratorByFinishes {
                HStack {
                    SectionLabel(NSLocalizedString("Top Narrator", comment: "Completed: most finished narrator"))
                    Text(String(format: NSLocalizedString("%@ · %d finished", comment: "Completed: narrator and count"), top.name, top.count))
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                }
            }
        }
    }

    private func days(_ seconds: TimeInterval) -> String {
        let days = max(seconds / 86_400, 0.1)
        return String(format: NSLocalizedString("%@ days", comment: "Completed: duration in days"),
                      days.formatted(.number.precision(.fractionLength(days < 10 ? 1 : 0))))
    }

    private func figure(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 22, weight: .bold))
            SectionLabel(caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
