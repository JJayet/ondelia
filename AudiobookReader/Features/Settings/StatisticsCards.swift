import SwiftUI

struct StatCardView: View {
    let title: String
    let value: String
    var subtitle: String = ""
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text(value)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primaryText)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondaryText)
                    }
                }

                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondaryText)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .glassEffect(in:.rect(cornerRadius: 16))
    }
}

struct AchievementView: View {
    let icon: String
    let title: String
    let value: String
    let isUnlocked: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(isUnlocked ? .yellow : .secondaryText)

            Text(title)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.primaryText)
                .multilineTextAlignment(.center)

            Text(value)
                .font(.caption2)
                .foregroundColor(.secondaryText)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .glassEffect(in:.rect(cornerRadius: 12))
        .opacity(isUnlocked ? 1.0 : 0.6)
    }
}
