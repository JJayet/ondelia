import SwiftUI

struct StatisticsView: View {
    let statistics: ReadingStatistics
    private let themeManager = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 24) {
                    VStack(spacing: 16) {
                        VStack(spacing: 8) {
                            Text(NSLocalizedString("This Month", comment: "This month progress header"))
                                .font(.headline)
                                .foregroundStyle(Color.primaryText)

                            Text(statistics.formattedMonthlyProgress)
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundStyle(.tint)

                            Text(String(format: NSLocalizedString("of %@ goal", comment: "Monthly goal progress text"), statistics.formattedMonthlyGoal))
                                .font(.subheadline)
                                .foregroundStyle(Color.secondaryText)
                        }

                        // Progress Ring
                        ZStack {
                            Circle()
                                .stroke(Color.secondaryBackground, lineWidth: 12)

                            Circle()
                                .trim(from: 0, to: statistics.monthlyGoalProgress)
                                .stroke(
                                    LinearGradient(
                                        colors: [.accentColor, .accentColor.opacity(0.6)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut(duration: 1), value: statistics.monthlyGoalProgress)

                            Text("\(Int(statistics.monthlyGoalProgress * 100))%")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.primaryText)
                        }
                        .frame(width: 150, height: 150)
                    }
                    .padding(24)
                    .glassEffect(in:.rect(cornerRadius: 20))

                    // Statistics Grid
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        StatCardView(
                            title: NSLocalizedString("Total Time", comment: "Total time stat card title"),
                            value: statistics.formattedTotalTime,
                            icon: "clock",
                            color: .blue
                        )

                        StatCardView(
                            title: NSLocalizedString("Books Completed", comment: "Books completed stat card title"),
                            value: "\(statistics.booksCompleted)",
                            icon: "books.vertical",
                            color: .green
                        )

                        StatCardView(
                            title: NSLocalizedString("Current Streak", comment: "Current streak stat card title"),
                            value: "\(statistics.currentStreak)",
                            subtitle: NSLocalizedString("days", comment: "Days unit for stat card"),
                            icon: "flame",
                            color: .red
                        )
                    }

                }
                .padding()
            }
            .background(Color.primaryBackground.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("Statistics", comment: "Statistics view title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Done", comment: "Done button")) { dismiss() }
                }
            }
        }
    }
}

#Preview("Statistics") {
    StatisticsView(statistics: ReadingStatistics())
}
