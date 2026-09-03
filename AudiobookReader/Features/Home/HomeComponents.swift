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
                    .foregroundStyle(Color.primaryText)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText)
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
                .foregroundStyle(color)

            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(Color.primaryText)

            Text(title)
                .font(.caption)
                .foregroundStyle(Color.secondaryText)
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
                            .foregroundStyle(Color.secondaryText)
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
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(2)

                    Text(audiobook.author ?? AudiobookModel.unknownAuthor)
                        .font(.caption)
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)

                    if audiobook.lastPlayed > Date.distantPast {
                        Text(
                            RelativeDateTimeFormatter().localizedString(
                                for: audiobook.lastPlayed,
                                relativeTo: Date()
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(.tint)
                    }
                }
            }
            .frame(width: 120)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct MonthlyGoalCardView: View {
    let statistics: ReadingStatistics

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
                    .foregroundStyle(Color.primaryText)

                    Text(
                        String(
                            format: NSLocalizedString("%@ of %@", comment: "Monthly goal progress: listened time of goal time"),
                            statistics.formattedMonthlyProgress,
                            statistics.formattedMonthlyGoal
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(Color.secondaryText)
                }

                Spacer()

                Text("\(Int(statistics.monthlyGoalProgress * 100))%")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.tint)
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
