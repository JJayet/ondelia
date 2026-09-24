import SwiftUI

/// A collection as a compact tile for the wide library: a stack of covers, the name, the count
/// and length, and a progress hairline. The full-width `CollectionCardView` stays for the phone.
struct CollectionTileView: View {
    let group: CollectionGroup
    let onOpen: () -> Void

    var body: some View {
        Button {
            withHapticFeedback { onOpen() }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: -38) {
                    ForEach(Array(group.books.prefix(3)), id: \.id) { book in
                        CoverArtView(audiobook: book, size: 62, cornerRadius: 9)
                            .shadow(color: .black.opacity(0.4), radius: 6, x: -3, y: 4)
                    }
                }
                .frame(height: 62, alignment: .leading)

                Text(group.name)
                    .font(.system(size: 14.5, weight: .semibold))
                    .lineLimit(1)
                    .padding(.top, 11)

                Text("\(group.countLabel) · \(group.totalDuration.hoursMinutesFormatted)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 3)

                ProgressLine(value: group.progressFraction, height: 3)
                    .padding(.top, 9)
            }
            .padding(13)
            .frame(width: 200, alignment: .leading)
            .contentShape(Rectangle())
            .glassCard(cornerRadius: 17)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(group.name)
        .accessibilityValue(group.countLabel)
    }
}
