import SwiftUI

/// A collection as a compact tile: a stack of covers, the name, the count
/// and length, and a progress hairline, on the Library's Collections strip.
struct CollectionTileView: View {
    let group: CollectionGroup
    let onOpen: () -> Void
    var width: CGFloat = 200

    var body: some View {
        Button {
            withHapticFeedback { onOpen() }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                CollectionCovers(sources: group.coverSources, size: 62, overlap: 38 / 62)

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
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
            .glassCard(cornerRadius: 17)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(group.name)
        .accessibilityValue(group.countLabel)
    }
}
