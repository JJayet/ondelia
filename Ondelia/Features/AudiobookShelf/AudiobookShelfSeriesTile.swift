import SwiftUI

/// A server series not stored as a Collection, as a compact tile for the wide Library, drawn
/// like `CollectionTileView`.
struct AudiobookShelfSeriesTile: View {
    let series: AudiobookShelfAPI.Series
    var width: CGFloat = 200

    private var books: [AudiobookShelfAPI.Item] { series.books ?? [] }

    var body: some View {
        NavigationLink(value: AudiobookShelfRoute.series(series)) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: -38) {
                    ForEach(books.prefix(3)) { book in
                        AudiobookShelfCover(item: book.id, size: 62, cornerRadius: 9)
                    }
                }
                .frame(height: 62, alignment: .leading)

                Text(series.name)
                    .font(.system(size: 14.5, weight: .semibold))
                    .lineLimit(1)
                    .padding(.top, 11)

                Text(String(
                    format: NSLocalizedString("%d books", comment: "AudiobookShelf: number of books in a series or by an author"),
                    books.count
                ))
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 3)
            }
            .padding(13)
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
            .glassCard(cornerRadius: 17)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { withHapticFeedback {} })
        .audiobookShelfDownloadAllMenu(.series(series), name: series.name)
    }
}

extension View {
    /// What a screen showing server series and books needs: where their links lead, which
    /// server books are in the Library, and the server library for Download All. The server
    /// shelf, and the Library while it shows server audiobooks.
    func serverSeriesDestinations(library: String) -> some View {
        self
            .environment(\.audiobookShelfLibraryBooks, AudiobookShelfService.shared.libraryBooks)
            .environment(\.audiobookShelfLibrary, library)
            .navigationDestination(for: AudiobookShelfRoute.self) { route in
                switch route {
                case .series(let series): AudiobookShelfSeriesView(series: series, library: library)
                case .author(let author): AudiobookShelfAuthorView(author: author, library: library)
                }
            }
    }
}
