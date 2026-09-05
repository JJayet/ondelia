import SwiftUI

/// The streak card that opens the library: a ring for the month's goal wrapped around the
/// current streak, and the month's own numbers beside it.
struct StatisticsCardView: View {
    let statistics: ReadingStatistics
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                StreakRing(progress: statistics.monthlyGoalProgress, days: statistics.currentStreak)
                    .frame(width: 66, height: 66)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(NSLocalizedString("Current Streak", comment: "Current streak stat card title"))
                            .font(.system(size: 14.5, weight: .semibold))
                        Spacer()
                        Text(statistics.formattedTotalTime)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    ProgressLine(value: statistics.monthlyGoalProgress, height: 6)

                    Text(
                        String(
                            format: NSLocalizedString("%@ this month · of %@ goal", comment: "Monthly listening against the goal"),
                            statistics.formattedMonthlyProgress,
                            statistics.formattedMonthlyGoal
                        )
                    )
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .glassCard()
        }
        .buttonStyle(.plain)
    }
}

/// Goal ring with the streak count in the middle.
struct StreakRing: View {
    let progress: Double
    let days: Int
    var lineWidth: CGFloat = 6
    var numberSize: CGFloat = 19

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 1.2), value: progress)

            VStack(spacing: 1) {
                Text("\(days)")
                    .font(.system(size: numberSize, weight: .bold))
                Text(NSLocalizedString("days", comment: "Days unit for stat card").uppercased())
                    .font(.system(size: numberSize * 0.4, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(lineWidth / 2)
    }
}
