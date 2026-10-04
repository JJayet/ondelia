import SwiftUI

/// A Collection as a row of the Collections screen: a stack of covers, the name, what kind it
/// is, the count and length, and the progress.
struct CollectionRowView: View {
    let group: CollectionGroup

    var body: some View {
        HStack(spacing: 13) {
            CollectionCovers(sources: group.coverSources, size: 46, overlap: 27 / 46)
                .frame(width: 84, alignment: .leading)

            VStack(alignment: .leading, spacing: 0) {
                Text(group.name)
                    .font(.system(size: 14.5, weight: .semibold))
                    .lineLimit(1)
                Text(kind)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                HStack(spacing: 5) {
                    if group.serverSeries != nil { Image(systemName: "icloud") }
                    Text(verbatim: "\(group.countLabel) · \(group.totalDuration.hoursMinutesFormatted)")
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 3)
                if group.progressFraction > 0 {
                    HStack(spacing: 8) {
                        ProgressLine(value: group.progressFraction, height: 3)
                        Text(group.progressFraction, format: .percent.precision(.fractionLength(0)))
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var kind: String {
        if let server = group.serverSeries {
            return server.isServerCollection
                ? NSLocalizedString("Collection · server", comment: "Collections screen: a collection from an AudiobookShelf server")
                : NSLocalizedString("Series · server", comment: "Collections screen: a series from an AudiobookShelf server")
        }
        return group.isSeries
            ? NSLocalizedString("Series · Hardcover", comment: "Collections screen: a series from Hardcover")
            : NSLocalizedString("My Collection", comment: "Collections screen: a hand-made collection")
    }
}

/// A server collection or series with nothing of it in the Library yet: dimmed, and the count
/// says so.
struct ServerOnlyCollectionRowView: View {
    let series: AudiobookShelfAPI.Series

    var body: some View {
        HStack(spacing: 13) {
            CollectionCovers(sources: series.coverSources, size: 46, overlap: 27 / 46)
                .frame(width: 84, alignment: .leading)
                .opacity(0.55)

            VStack(alignment: .leading, spacing: 0) {
                Text(series.name)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(series.isServerCollection
                    ? NSLocalizedString("Collection · server", comment: "Collections screen: a collection from an AudiobookShelf server")
                    : NSLocalizedString("Series · server", comment: "Collections screen: a series from an AudiobookShelf server"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                HStack(spacing: 5) {
                    Image(systemName: "icloud")
                    Text(String(
                        format: NSLocalizedString("%d books · none here", comment: "Collections screen: server books, none of them in the Library"),
                        series.books?.count ?? 0
                    ))
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
