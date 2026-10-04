import SwiftUI

/// Up to three covers of a collection, each overlapping the one before: the Library's books and,
/// for a server series or collection, the server's books it has not joined yet.
struct CollectionCovers: View {
    enum Source: Identifiable {
        case book(AudiobookModel)
        case server(String)

        var id: String {
            switch self {
            case .book(let book): book.id.uuidString
            case .server(let item): "server-\(item)"
            }
        }
    }

    let sources: [Source]
    /// Each cover's side; nil fans them across a square as wide as the space given, as a grid
    /// cell's cover does.
    var size: CGFloat?
    /// How much of each cover the next one hides.
    var overlap: CGFloat = 0.6

    var body: some View {
        if let size {
            HStack(spacing: -size * overlap) { covers(size: size) }
                .frame(height: size, alignment: .leading)
        } else {
            GeometryReader { geometry in
                let width = geometry.size.width
                // One cover fills the square; more step across it, the front one largest.
                let side = sources.count > 1 ? width * 0.78 : width
                let step = sources.count > 1 ? (width - side) / CGFloat(sources.count - 1) : 0
                ZStack(alignment: .bottomLeading) {
                    ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                        cover(source, size: side, cornerRadius: side * 0.09)
                            .offset(x: step * CGFloat(index), y: -step * CGFloat(sources.count - 1 - index))
                    }
                }
                .frame(width: width, height: width, alignment: .bottomLeading)
            }
            .aspectRatio(1, contentMode: .fit)
        }
    }

    private func covers(size: CGFloat) -> some View {
        ForEach(sources) { cover($0, size: size, cornerRadius: size * 0.17) }
    }

    private func cover(_ source: Source, size: CGFloat, cornerRadius: CGFloat) -> some View {
        CollectionCover(source: source, size: size, cornerRadius: cornerRadius)
            .shadow(color: .black.opacity(0.4), radius: 6, x: -3, y: 4)
    }
}

/// One cover: a Library book's, or a server book's.
struct CollectionCover: View {
    let source: CollectionCovers.Source
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        switch source {
        case .book(let book): CoverArtView(audiobook: book, size: size, cornerRadius: cornerRadius)
        case .server(let item): AudiobookShelfCover(item: item, size: size, cornerRadius: cornerRadius)
        }
    }
}

extension CollectionGroup {
    /// The first three covers, in the collection's order, server books included.
    @MainActor
    var coverSources: [CollectionCovers.Source] {
        volumes(showMissing: false).lazy.compactMap { volume -> CollectionCovers.Source? in
            switch volume {
            case .owned(let book): .book(book)
            case .server(let item): .server(item.id)
            case .missing: nil
            }
        }
        .prefix(3)
        .map { $0 }
    }
}

extension AudiobookShelfAPI.Series {
    var coverSources: [CollectionCovers.Source] {
        (books ?? []).prefix(3).map { .server($0.id) }
    }
}

/// A collection in the Collections grid, sized like the Library's book cells.
struct CollectionGridItemView: View {
    let group: CollectionGroup
    var columns = 2
    let onOpen: () -> Void

    var body: some View {
        Button {
            withHapticFeedback { onOpen() }
        } label: {
            CollectionGridCell(
                covers: group.coverSources,
                name: group.name,
                meta: "\(group.countLabel) · \(group.totalDuration.hoursMinutesFormatted)",
                progress: group.progressFraction,
                columns: columns
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(group.name)
        .accessibilityValue(group.countLabel)
    }
}

/// A server collection or series with nothing in the Library yet, in the Collections grid.
struct ServerOnlyCollectionGridItemView: View {
    let series: AudiobookShelfAPI.Series
    var columns = 2

    var body: some View {
        NavigationLink(value: AudiobookShelfRoute.series(series)) {
            CollectionGridCell(
                covers: series.coverSources,
                name: series.name,
                meta: String(
                    format: NSLocalizedString("%d books · none here", comment: "Collections screen: server books, none of them in the Library"),
                    series.books?.count ?? 0
                ),
                progress: 0,
                columns: columns
            )
            .opacity(0.7)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { withHapticFeedback {} })
        .audiobookShelfDownloadAllMenu(.series(series), name: series.name)
    }
}

/// The cell itself, laid out like `AudiobookGridItemView`: the covers, a progress hairline on
/// their bottom edge, the name and the count.
private struct CollectionGridCell: View {
    let covers: [CollectionCovers.Source]
    let name: String
    let meta: String
    let progress: Double
    let columns: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CollectionCovers(sources: covers)
                .overlay(alignment: .bottom) {
                    if progress > 0 { ProgressLine(value: progress, height: 3) }
                }
            Text(name)
                .font(.system(size: columns >= 3 ? 11.5 : 12.5, weight: .semibold))
                .lineLimit(columns >= 4 ? 1 : 2)
                .multilineTextAlignment(.leading)
            if columns < 4 {
                Text(meta)
                    .font(.system(size: columns >= 3 ? 10 : 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
