import SwiftUI

struct StatisticsView: View {
    @ObservedObject var statistics: ReadingStatistics
    @StateObject private var themeManager = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 24) {
                    VStack(spacing: 16) {
                        VStack(spacing: 8) {
                            Text(NSLocalizedString("This Month", comment: "This month progress header"))
                                .font(.headline)
                                .foregroundColor(.primaryText)

                            Text(statistics.formattedMonthlyProgress)
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundColor(.accentColor)

                            Text(String(format: NSLocalizedString("of %@ goal", comment: "Monthly goal progress text"), statistics.formattedMonthlyGoal))
                                .font(.subheadline)
                                .foregroundColor(.secondaryText)
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
                                .foregroundColor(.primaryText)
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
                            title: NSLocalizedString("Average Speed", comment: "Average speed stat card title"),
                            value: String(format: "%.1fx", statistics.averageSpeed),
                            icon: "speedometer",
                            color: .orange
                        )

                        StatCardView(
                            title: NSLocalizedString("Current Streak", comment: "Current streak stat card title"),
                            value: "\(statistics.currentStreak)",
                            subtitle: NSLocalizedString("days", comment: "Days unit for stat card"),
                            icon: "flame",
                            color: .red
                        )
                    }

                    // Achievement Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text(NSLocalizedString("Achievements", comment: "Achievements section header"))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primaryText)

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            AchievementView(
                                icon: "trophy.fill",
                                title: NSLocalizedString("Longest Streak", comment: "Longest streak achievement title"),
                                value: "\(statistics.longestStreak) \(NSLocalizedString("days", comment: "Days unit"))",
                                isUnlocked: statistics.longestStreak >= 7
                            )

                            AchievementView(
                                icon: "book.fill",
                                title: NSLocalizedString("First Book", comment: "First book achievement title"),
                                value: NSLocalizedString("Complete", comment: "Achievement completion status"),
                                isUnlocked: statistics.booksCompleted >= 1
                            )

                            AchievementView(
                                icon: "clock.fill",
                                title: NSLocalizedString("10 Hours", comment: "10 hours achievement title"),
                                value: statistics.totalListeningTime >= 36000 ? NSLocalizedString("Complete", comment: "Achievement completion status") : NSLocalizedString("In Progress", comment: "Achievement in progress status"),
                                isUnlocked: statistics.totalListeningTime >= 36000
                            )
                        }
                    }
                }
                .padding()
            }
            .background(Color.primaryBackground.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("Statistics", comment: "Statistics view title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Done", comment: "Done button")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        .tint(themeManager.accentColor.color)
    }
}

#Preview("Statistics") {
    StatisticsView(statistics: ReadingStatistics())
}
