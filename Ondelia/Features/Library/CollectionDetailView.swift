import SwiftUI
import TipKit

/// A collection on its own screen: fanned covers, the totals, one progress bar per book, the
/// resume button, the back-to-back toggle, then the books in the collection's order.
struct CollectionDetailView: View {
    let collection: CollectionModel
    let bookActions: BookActions
    let onSelectBook: (AudiobookModel) -> Void
    let onRename: (CollectionModel) -> Void
    let onDelete: (CollectionModel) -> Void

    @Environment(\.playerRouter) private var playerRouter
    @AppStorage(CollectionGroup.showMissingKey) var showMissing = true
    let manager = AudiobookManager.shared
    private let audioManager = GlobalAudioManager.shared

    var group: CollectionGroup {
        // Streamed books hide while the server is off, as on the shelf.
        let books = AudiobookShelfCatalog.shared.visible(
            manager.orderedBooks(in: collection), linked: AudiobookShelfService.shared.libraryBooks
        )
        return CollectionGroup(collection: collection, books: books)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                hero
                TipView(AutoContinueTip())
                progressCard
                booksSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(TintedBackground(tint: CoverTintCache.tint(for: group.books.first), intensity: 1))
        .scrollContentBackground(.hidden)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text((group.isSeries
                    ? NSLocalizedString("Series", comment: "Collection detail header: a Hardcover series")
                    : NSLocalizedString("Collection", comment: "Collection detail header: hand-made")).uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu { menuItems } label: { Image(systemName: "ellipsis") }
                    .simultaneousGesture(TapGesture().onEnded { withHapticFeedback {} })
                    .accessibilityLabel(NSLocalizedString("More", comment: "Book actions menu"))
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 8) {
            ZStack {
                // First book on top, each next one a step behind it.
                // Server books too: a server series may hold one Library book among many.
                let covers = group.coverSources
                ForEach(Array(covers.enumerated()), id: \.element.id) { index, source in
                    let spread = Double(index) - Double(covers.count - 1) / 2
                    CollectionCover(source: source, size: 118, cornerRadius: 18)
                        .rotationEffect(.degrees(spread * 12))
                        .offset(x: spread * 62, y: abs(spread) * 6)
                        .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
                        .zIndex(Double(-index))
                }
            }
            .frame(height: 150)
            .padding(.top, 8)

            Text(group.name)
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)

            Text(credits)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if group.isSeries {
                Label(
                    NSLocalizedString("Series and volumes filled in by Hardcover", comment: "Collection detail: source badge"),
                    systemImage: "checkmark"
                )
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(.green.opacity(0.14), in: Capsule())
                .padding(.top, 4)
            }
        }
    }

    /// "Brandon Sanderson · 3 volumes · 68h 32m".
    private var credits: String {
        [group.author, group.countLabel, group.totalDuration.hoursMinutesFormatted]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    // MARK: - Progress

    private var progressCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(
                    format: group.isSeries
                        ? NSLocalizedString("%d%% of the series", comment: "Series progress")
                        : NSLocalizedString("%d%% listened", comment: "Percent of the book heard"),
                    Int(group.progressFraction * 100)
                ))
                .font(.system(size: 13.5, weight: .semibold))

                Spacer()

                Text(String(
                    format: NSLocalizedString("%@ left", comment: "Remaining listening time"),
                    group.remaining.hoursMinutesFormatted
                ))
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
            }
            .padding(.bottom, 10)

            segmentedProgress

            if let current = group.currentBook {
                Button { play(current) } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "play.fill").font(.system(size: 14, weight: .bold))
                        Text(resumeTitle(for: current))
                            .font(.system(size: 15.5, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(.tint, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(NSLocalizedString("Play back to back", comment: "Collection toggle: chain the books"))
                        .font(.system(size: 15))
                    Text(NSLocalizedString("The next book starts when this one ends", comment: "Collection toggle explanation"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
                    get: { collection.autoContinue },
                    set: { manager.setAutoContinue($0, for: collection) }
                ))
                .labelsHidden()
            }
            .padding(.top, 16)
        }
        .padding(18)
        .glassCard(cornerRadius: 28)
    }

    /// One bar per book, as wide as the book is long, with its volume label underneath.
    private var segmentedProgress: some View {
        let total = max(group.totalDuration, 1)
        let gap: CGFloat = 4
        let books = group.books
        return GeometryReader { geometry in
            let available = geometry.size.width - gap * CGFloat(max(books.count - 1, 0))
            VStack(spacing: 6) {
                HStack(spacing: gap) {
                    ForEach(books, id: \.id) { book in
                        ProgressLine(value: book.progressFraction, height: 6, color: book.isFinished ? .green : nil)
                            .frame(width: max(available * book.duration / total, 6), height: 6)
                    }
                }
                HStack(spacing: gap) {
                    ForEach(Array(books.enumerated()), id: \.element.id) { index, book in
                        Text(volumeLabel(book, index: index))
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1)
                            .lineLimit(1)
                            .foregroundStyle(.tertiary)
                            .frame(width: max(available * book.duration / total, 6), alignment: .leading)
                    }
                }
            }
        }
        .frame(height: 26)
    }

    // MARK: - Helpers

    /// Hardcover's volume badge in a series; the row's position in a hand-made collection,
    /// where a badge from some other series would mean nothing.
    func volumeLabel(_ book: AudiobookModel, index: Int) -> String {
        (group.isSeries ? book.hardcover?.volumeBadge : nil) ?? "#\(index + 1)"
    }

    /// "Resume #1 · ch. 14", or "Play #1" for a book not started.
    private func resumeTitle(for book: AudiobookModel) -> String {
        let index = group.books.firstIndex { $0.id == book.id } ?? 0
        let label = volumeLabel(book, index: index)
        guard book.currentPosition > 0 else {
            return String(format: NSLocalizedString("Play %@", comment: "Collection: start a volume"), label)
        }
        if let chapter = currentChapterNumber(of: book) {
            return String(format: NSLocalizedString("Resume %@ · ch. %d", comment: "Collection: resume a volume at a chapter"), label, chapter)
        }
        return String(format: NSLocalizedString("Resume %@", comment: "Collection: resume a volume"), label)
    }

    /// 1-based chapter the saved position sits in; nil without chapters.
    func currentChapterNumber(of book: AudiobookModel) -> Int? {
        let chapters = book.sortedChapters
        guard !chapters.isEmpty else { return nil }
        return (chapters.lastIndex { $0.startTime <= book.currentPosition } ?? 0) + 1
    }

    func play(_ book: AudiobookModel) {
        withHapticFeedback(.medium) {}
        audioManager.loadAudiobook(book)
        audioManager.startPlaybackAfterOpeningBook()
        playerRouter?.present(book)
    }

    @ViewBuilder
    private var menuItems: some View {
        Menu {
            ForEach(CollectionSort.allCases.filter { $0 != .seriesPosition || group.isSeries }, id: \.rawValue) { sort in
                Button { withHapticFeedback { manager.setSort(sort, for: collection) } } label: {
                    if collection.sort == sort {
                        Label(sort.displayName, systemImage: "checkmark")
                    } else {
                        Text(sort.displayName)
                    }
                }
            }
        } label: {
            Label(NSLocalizedString("Sort by", comment: "Search sort picker label"), systemImage: "arrow.up.arrow.down")
        }
        if !group.isSeries {
            Button { onRename(collection) } label: {
                Label(NSLocalizedString("Rename", comment: "Rename button"), systemImage: "pencil")
            }
        }
        Button(role: .destructive) { onDelete(collection) } label: {
            Label(NSLocalizedString("Delete Collection", comment: "Delete a collection, keeping its books"), systemImage: "trash")
        }
        .tint(.red)
    }
}
