import SwiftUI

struct StatisticsView: View {
    let statistics: ReadingStatistics
    @Environment(\.dismiss) private var dismiss
    /// The ring animates in from zero on appear, so opening the sheet reads as progress being
    /// counted up rather than a static gauge.
    @State private var ringProgress: Double = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    streakCard

                    HStack(spacing: 14) {
                        tile(
                            value: statistics.formattedMonthlyProgress,
                            caption: String(
                                format: NSLocalizedString("this month · %@ goal", comment: "Monthly goal caption"),
                                statistics.formattedMonthlyGoal
                            )
                        )
                        tile(
                            value: "\(statistics.booksCompleted)",
                            caption: NSLocalizedString("books completed", comment: "Books completed caption")
                        )
                    }

                    HStack(spacing: 14) {
                        tile(
                            value: statistics.formattedTotalTime,
                            caption: NSLocalizedString("listened in total", comment: "Total listening caption")
                        )
                        tile(
                            value: "\(statistics.longestStreak)",
                            caption: NSLocalizedString("longest streak, in days", comment: "Longest streak caption")
                        )
                    }
                }
                .padding(16)
            }
            .background(TintedBackground(intensity: 0.7))
            .scrollContentBackground(.hidden)
            .navigationTitle(NSLocalizedString("Statistics", comment: "Statistics view title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Done", comment: "Done button")) { dismiss() }
                }
            }
            .task {
                ringProgress = statistics.monthlyGoalProgress
            }
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

    private func tile(value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 26, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: 24)
    }
}

#Preview("Statistics") {
    StatisticsView(statistics: ReadingStatistics())
}
