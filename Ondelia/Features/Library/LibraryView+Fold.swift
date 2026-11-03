import SwiftUI

// MARK: - Either side of the fold (design 9a)
//
// iPhone Duo: what to pick up on the left — resume, the queue, four collections — and the
// shelf on the right, each half a screen of its own.
extension LibraryView {
    func foldPicks(_ shelf: Shelf) -> some View {
        VStack(spacing: 0) {
            wideHeader(shelf.books)
            if AudiobookShelfService.shared.isSignedIn, !blendsServer { sourcePicker }
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !continueReading.isEmpty {
                        ContinueReadingSection(entries: continueReading, headerPadding: nil, rowPadding: nil, wide: true, stacked: true) {
                            playAndPresent($0)
                        }
                    }
                    if !queuedBooks.isEmpty {
                        QueueSectionView(books: queuedBooks, horizontalPadding: nil, onSelect: playQueued)
                    }
                    if hasCollections(shelf.groups) { collectionsGrid(shelf.groups) }
                }
                .padding(.vertical)
            }
        }
    }

    /// The table needs the whole width for its columns; half a screen reads it as the list.
    @ViewBuilder
    func foldShelf(_ shelf: Shelf) -> some View {
        if showsServer {
            AudiobookShelfShelfView()
        } else {
            Group {
                switch viewMode {
                case .grid: gridModeContent(shelf, shelfOnly: true)
                case .list, .table: listModeContent(shelf, shelfOnly: true)
                }
            }
            .serverSeriesDestinations(library: AudiobookShelfService.shared.primary?.library ?? "")
        }
    }
}
