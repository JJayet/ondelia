import SwiftUI

enum BookDetailTab: Hashable { case chapters, bookmarks, about }

// MARK: - Either side of the fold (design 13)
//
// iPhone Duo: the cover beside the title and the progress card at the bottom, in thumb's reach,
// on the left; chapters, bookmarks and the book's details as tabs on the right, where they
// used to be sheets.
extension BookDetailView {
    var foldSheet: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 18) {
                        CoverArtView(audiobook: audiobook, size: 140, cornerRadius: 18)
                            .shadow(color: .black.opacity(0.4), radius: 18, y: 10)
                        identity
                    }
                    chips(alignment: .leading).padding(.top, 16)
                    Spacer(minLength: 18)
                    progressCard(sheets: false)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let link = audiobook.hardcover, let series = link.seriesName {
                Text([series, link.volumeBadge].compactMap { $0 }.joined(separator: " · ").uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(.tint)
            }
            Text(audiobook.title ?? AudiobookModel.unknownTitle)
                .font(.system(size: 26, weight: .bold))
                .lineLimit(3)
                .minimumScaleFactor(0.7)
            Text(String(
                format: NSLocalizedString("Written by %@", comment: "Book detail: author credit"),
                audiobook.author ?? AudiobookModel.unknownAuthor
            ))
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            if let narrator = audiobook.narrator {
                Text(String(format: NSLocalizedString("Narrated by %@", comment: "Book detail: narrator credit"), narrator))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Tabs

    var foldTabs: some View {
        VStack(spacing: 0) {
            Picker(NSLocalizedString("View", comment: "Collections screen: list or grid"), selection: $foldTab) {
                Text(verbatim: "\(NSLocalizedString("Chapters", comment: "Chapter list sheet title")) \(chapters.count)")
                    .tag(BookDetailTab.chapters)
                Text(verbatim: "\(NSLocalizedString("Bookmarks", comment: "Bookmarks button title")) \(audiobook.bookmarks.count)")
                    .tag(BookDetailTab.bookmarks)
                Text(NSLocalizedString("About", comment: "Book detail: summary and details tab"))
                    .tag(BookDetailTab.about)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            switch foldTab {
            case .chapters: chaptersTab
            case .bookmarks: bookmarksTab
            case .about: aboutTab
            }
        }
    }

    /// Plays the book from `time`: the seek is queued when this book is not the one loaded.
    private func play(from time: TimeInterval) {
        audioManager.loadAudiobook(audiobook)
        audioManager.seek(to: time)
        play()
    }

    private var chaptersTab: some View {
        let current = currentChapter.flatMap { now in chapters.firstIndex { $0.id == now.id } }
        let position = audiobook.currentPosition
        return ScrollViewReader { reader in
            ScrollView {
                // Not lazy: `scrollTo` needs the resume row to exist.
                VStack(spacing: 0) {
                    ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                        WideChapterRow(
                            chapter: chapter,
                            title: chapter.title ?? String(
                                format: NSLocalizedString("Chapter %d", comment: "Default chapter title with number"),
                                chapter.chapterNumber
                            ),
                            state: rowState(index: index, current: current, chapter: chapter, position: position),
                            isPlaying: false,
                            currentLabel: String(
                                format: NSLocalizedString("resume here · %@", comment: "Book detail: the chapter playback resumes in, and where"),
                                (position - chapter.startTime).clockFormatted
                            )
                        ) { play(from: chapter.startTime) }
                        .id(chapter.id)
                    }
                }
                .glassCard(cornerRadius: 20)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .onAppear {
                if let id = currentChapter?.id { reader.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func rowState(index: Int, current: Int?, chapter: ChapterModel, position: TimeInterval) -> WideChapterRow.State {
        guard let current else { return .upcoming }
        if index < current { return .heard }
        if index > current { return .upcoming }
        let span = max(chapter.endTime - chapter.startTime, 1)
        return .current(remaining: max(chapter.endTime - position, 0), fraction: (position - chapter.startTime) / span)
    }

    @ViewBuilder
    private var bookmarksTab: some View {
        let bookmarks = audiobook.bookmarks.sorted { $0.timestamp < $1.timestamp }
        if bookmarks.isEmpty {
            ContentUnavailableView(
                NSLocalizedString("No bookmarks yet", comment: "No bookmarks empty state title"),
                systemImage: "bookmark"
            )
            .frame(maxHeight: .infinity)
        } else {
            List(bookmarks, id: \.id) { bookmark in
                BookmarkRowView(
                    bookmark: bookmark,
                    onTap: { play(from: bookmark.timestamp) },
                    onDelete: { AudiobookManager.shared.deleteBookmark(bookmark) }
                )
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var aboutTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summary
                metaLine
                if let genres = audiobook.hardcover?.genres, !genres.isEmpty {
                    Text(genres.prefix(4).joined(separator: " · "))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                seriesList
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    /// The other books of its collection, in the collection's order, this one lit.
    @ViewBuilder
    private var seriesList: some View {
        let manager = AudiobookManager.shared
        if let collection = manager.collections.first(where: { $0.bookIDs.contains(audiobook.id) }) {
            let books = manager.orderedBooks(in: collection)
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(NSLocalizedString("In the Series", comment: "Book detail: the other books of its collection"))
                    .padding(.bottom, 8)
                ForEach(Array(books.enumerated()), id: \.element.id) { index, book in
                    let isThis = book.id == audiobook.id
                    HStack(spacing: 12) {
                        CoverArtView(audiobook: book, size: 40, cornerRadius: 8)
                        Text(verbatim: "\((collection.isSeries ? book.hardcover?.volumeBadge : nil) ?? "#\(index + 1)") · \(book.title ?? AudiobookModel.unknownTitle)")
                            .font(.system(size: 14.5, weight: isThis ? .semibold : .regular))
                            .foregroundStyle(isThis ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 7)
                }
            }
        }
    }
}
