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
                .foregroundStyle(color)

            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text(value)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.primaryText)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Color.secondaryText)
                    }
                }

                Text(title)
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .glassEffect(in:.rect(cornerRadius: 16))
    }
}

