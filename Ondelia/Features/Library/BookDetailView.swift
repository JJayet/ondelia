import SwiftUI

/// What a book looks like before it is playing: the cover as a lit header, what the book is,
/// how far in you are, and the ways in — resume, chapters, bookmarks.
struct BookDetailView: View {
    let audiobook: AudiobookModel
    let actions: BookActions

    @Environment(\.playerRouter) private var playerRouter
    let audioManager = GlobalAudioManager.shared

    @State var showingChapters = false
    @State var showingBookmarks = false
    @State var fileBytes: Int64?
    @State var seriesOptions: [HardcoverAPI.SeriesRef] = []
    @State var showingSeriesPicker = false
    /// The right half's tab around the iPhone Duo's fold (BookDetailView+Fold.swift).
    @State var foldTab = BookDetailTab.chapters

    var chapters: [ChapterModel] { audiobook.sortedChapters }

    var remaining: TimeInterval {
        max(audiobook.duration - audiobook.currentPosition, 0)
    }

    var body: some View {
        // iPhone Duo around its fold (design 13): the sheet and its actions on the left, and
        // on the right what you look through, as tabs instead of sheets.
        FoldSplit {
            foldSheet
        } secondary: {
            foldTabs
        } fallback: {
            ScrollView {
                VStack(spacing: 0) {
                    header

                    VStack(spacing: 14) {
                        titleBlock
                        chips()
                        progressCard()
                        metaLine
                        summary
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 30)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
            }
            // Under the bar: the blurred cover is the header's light.
            .ignoresSafeArea(edges: .top)
        }
        .background(TintedBackground(tint: CoverTintCache.tint(for: audiobook), intensity: 1))
        // The blurb, genres, moods and content warnings come from Hardcover the first time this
        // screen is opened, and are stored on the link afterwards.
        .task { await HardcoverService.shared.refreshDetails(for: audiobook) }
        .task { await backfillNarrator() }
        .task {
            guard let url = audiobook.resolvedFileURL else { return }
            fileBytes = await Task.detached { StorageUsage.bytes(at: url) }.value
        }
        .scrollContentBackground(.hidden)
        // The bar stays, transparent: hiding it also disables the swipe-back gesture. The
        // system back button reads as a glass circle over the artwork, so no custom one.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    BookActionsMenu(audiobook: audiobook, actions: actions)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .simultaneousGesture(TapGesture().onEnded { withHapticFeedback {} })
                .accessibilityLabel(NSLocalizedString("More", comment: "Book actions menu"))
                .accessibilityIdentifier(AccessibilityIdentifiers.Library.bookActionsMenu)
            }
        }
        .sheet(isPresented: $showingChapters) {
            ChapterListView(chapters: chapters, currentChapter: currentChapter) { chapter in
                // The seek is queued when this book is not the one loaded: `loadAudiobook` is
                // asynchronous, and the load applies the pending position when it lands.
                audioManager.loadAudiobook(audiobook)
                audioManager.seek(to: chapter.startTime)
                showingChapters = false
                play()
            }
        }
        .sheet(isPresented: $showingBookmarks) {
            BookmarksView(audiobook: audiobook, globalAudioManager: audioManager)
        }
    }

    var currentChapter: ChapterModel? {
        let position = audiobook.currentPosition
        return chapters.last { position >= $0.startTime }
    }

    // MARK: - Header

    private var header: some View {
        ZStack(alignment: .bottom) {
            // The cover, blurred out to the full width, is the header's own light.
            if let cover = CoverImageCache.image(for: audiobook) {
                Image(uiImage: cover)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 300)
                    .blur(radius: 46)
                    .clipped()
            }

            LinearGradient(
                colors: [.black.opacity(0.2), .black.opacity(0.55), .black.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )

            CoverArtView(audiobook: audiobook, size: 186, cornerRadius: 22)
                .padding(.bottom, 14)
        }
        .frame(height: 300)
        .clipped()
    }

    // MARK: - Identity

    private var titleBlock: some View {
        VStack(spacing: 6) {
            Text(audiobook.title ?? AudiobookModel.unknownTitle)
                .font(.system(size: 23, weight: .bold))
                .multilineTextAlignment(.center)

            Text(String(
                format: NSLocalizedString("Written by %@", comment: "Book detail: author credit"),
                audiobook.author ?? AudiobookModel.unknownAuthor
            ))
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            if let narrator = audiobook.narrator {
                Text(String(
                    format: NSLocalizedString("Narrated by %@", comment: "Book detail: narrator credit"),
                    narrator
                ))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }

            if audiobook.hardcover != nil {
                HStack(spacing: 5) {
                    HardcoverLinkMark(size: 11)
                    Text(NSLocalizedString("Linked to Hardcover", comment: "Book is linked to a Hardcover entry"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 2)
            }
        }
    }

    /// Books imported before narrators were read carry none. Read it from the first audio file
    /// when the screen opens; nothing to write when the file has no narrator tag either.
    /// ponytail: a book with no tag repeats this one asset load on every open.
    private func backfillNarrator() async {
        guard audiobook.narrator == nil, let url = audiobook.resolvedFileURL else { return }
        let tracks = await AudiobookPlayer.makeTracks(at: url, fallbackDuration: audiobook.duration)
        guard let first = tracks.first?.url,
              let narrator = await MetadataExtractor.extractMetadata(from: first)?.narrator else { return }
        audiobook.narrator = narrator
        AudiobookManager.shared.swiftDataController.save()
    }

    func chips(alignment: Alignment = .center) -> some View {
        HStack(spacing: 8) {
            DetailChip(text: audiobook.duration.hoursMinutesFormatted)

            if !chapters.isEmpty {
                DetailChip(
                    text: String(
                        format: NSLocalizedString("%d chapters", comment: "Chapter count chip"),
                        chapters.count
                    )
                )
            }

            if let link = audiobook.hardcover {
                // Tapping asks Hardcover which series the book is in, and offers a choice when
                // there are several: a shared universe or an omnibus can put it in the wrong one.
                Button {
                    Task { await openSeriesPicker() }
                } label: {
                    DetailChip(
                        text: [link.seriesName, link.volumeBadge].compactMap { $0 }.joined(separator: " ")
                            .ifEmpty("Hardcover"),
                        icon: "checkmark",
                        tint: .green
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint(NSLocalizedString("Choose the series", comment: "Hardcover chip hint"))
                .confirmationDialog(
                    NSLocalizedString("Series", comment: "Series picker title"),
                    isPresented: $showingSeriesPicker,
                    titleVisibility: .visible
                ) { seriesPickerButtons }
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }

    // MARK: - Size and publication

    /// "743 MB · Published 15 March 2021", under the player card. Chips ran out of room for it.
    @ViewBuilder
    var metaLine: some View {
        let parts: [String] = [
            fileBytes.flatMap { $0 > 0 ? $0.formatted(.byteCount(style: .file)) : nil },
            audiobook.hardcover?.releaseDate.map {
                String(
                    format: NSLocalizedString("Published %@", comment: "Book detail: first publication date"),
                    $0.formatted(date: .long, time: .omitted)
                )
            }
        ].compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Summary

    @ViewBuilder
    var summary: some View {
        if let text = audiobook.hardcover?.summary, !text.isEmpty {
            Text(text)
                .font(.system(size: 13.5))
                .lineSpacing(4)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.top, 8)
        }
    }

    func play() {
        withHapticFeedback(.medium) {}
        audioManager.loadAudiobook(audiobook)
        audioManager.startPlaybackAfterOpeningBook()
        playerRouter?.present(audiobook)
    }
}

/// The pill row under a book's title: length, chapter count, Hardcover.
private struct DetailChip: View {
    let text: String
    var icon: String?
    var tint: Color?

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
            }
            Text(text)
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(tint ?? .secondary)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .glassEffect(.regular, in: Capsule())
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
