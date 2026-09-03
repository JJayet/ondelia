import SwiftUI

struct HomeSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primaryText)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondaryText)
            }
            .padding(.horizontal)

            content
        }
    }
}

struct QuickStatView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)

            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.primaryText)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondaryText)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .glassEffect(in: .rect(cornerRadius: 16))
    }
}

struct RecentlyPlayedCardView: View {
    let audiobook: AudiobookModel
    let onTap: () -> Void

    private var coverImage: UIImage? {
        guard let data = audiobook.coverImageData else { return nil }
        return UIImage(data: data)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Cover Art
                Group {
                    if let image = coverImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "book.closed")
                            .font(.system(size: 30))
                            .foregroundColor(.secondaryText)
                    }
                }
                .frame(width: 120, height: 80)
                .background(Color.secondaryBackground)
                .cornerRadius(12)
                .clipped()

                VStack(alignment: .leading, spacing: 4) {
                    Text(audiobook.title ?? AudiobookModel.unknownTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primaryText)
                        .lineLimit(2)

                    Text(audiobook.author ?? AudiobookModel.unknownAuthor)
                        .font(.caption)
                        .foregroundColor(.secondaryText)
                        .lineLimit(1)

                    if audiobook.lastPlayed > Date.distantPast {
                        Text(
                            RelativeDateTimeFormatter().localizedString(
                                for: audiobook.lastPlayed,
                                relativeTo: Date()
                            )
                        )
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                    }
                }
            }
            .frame(width: 120)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct MonthlyGoalCardView: View {
    @ObservedObject var statistics: ReadingStatistics

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        NSLocalizedString(
                            "Monthly Reading Goal",
                            comment: "Monthly reading goal card title"
                        )
                    )
                    .font(.headline)
                    .foregroundColor(.primaryText)

                    Text(
                        String(
                            format: NSLocalizedString("%@ of %@", comment: "Monthly goal progress: listened time of goal time"),
                            statistics.formattedMonthlyProgress,
                            statistics.formattedMonthlyGoal
                        )
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondaryText)
                }

                Spacer()

                Text("\(Int(statistics.monthlyGoalProgress * 100))%")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
            }

            ProgressView(value: statistics.monthlyGoalProgress)
                .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                .frame(height: 6)
                .background(Color.secondaryBackground)
                .cornerRadius(3)
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 16))
    }
}
