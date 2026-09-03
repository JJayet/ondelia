import SwiftUI

struct StatisticsCardView: View {
    let statistics: ReadingStatistics
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("This Month", comment: "This month statistics"))
                            .font(.caption)
                            .foregroundColor(.secondaryText)

                        Text(statistics.formattedMonthlyProgress)
                            .font(.title2)
                            .fontWeight(.bold)

                        Text(String(format: NSLocalizedString("of %@ goal", comment: "Goal progress text"), statistics.formattedMonthlyGoal))
                            .font(.caption)
                            .foregroundColor(.secondaryText)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(NSLocalizedString("Total", comment: "Total statistics"))
                            .font(.caption)
                            .foregroundColor(.secondaryText)

                        Text(statistics.formattedTotalTime)
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text(String(format: NSLocalizedString("%d books", comment: "Number of books completed"), statistics.booksCompleted))
                            .font(.caption)
                            .foregroundColor(.secondaryText)
                    }
                }

                ProgressView(value: statistics.monthlyGoalProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    .frame(height: 4)
            }
            .padding()
            .glassEffect(in:.rect(cornerRadius: 12))

        }
        .buttonStyle(PlainButtonStyle())
    }
}
