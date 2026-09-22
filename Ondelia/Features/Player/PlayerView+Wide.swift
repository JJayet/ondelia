import SwiftUI

extension PlayerView {
    // MARK: - Wide layout
    //
    // Regular width (iPad, Mac): the design's "platine posée". Cover and title sit up top, the
    // chapter table fills the middle, and the transport is docked across the whole width at the
    // bottom — the same frontier as the iPhone Duo fold, only wider.
    @ViewBuilder
    var wideLayout: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 32) {
                CoverArtView(audiobook: audiobook, size: 222, cornerRadius: 22)
                    .shadow(color: .black.opacity(0.45), radius: 24, y: 14)
                    .id(audiobook.id)

                VStack(alignment: .leading, spacing: 0) {
                    titleBlock
                    metaChips.padding(.top, 16).padding(.leading, 10)
                    chipRow
                        .frame(maxWidth: 440, alignment: .leading)
                        .padding(.top, 22)
                        .padding(.leading, 10)
                }
            }
            .padding(.top, 20)
            .padding(.horizontal, 24)

            chapterTable
                .padding(.top, 28)
                .padding(.horizontal, 24)

            playerTips
                .padding(.top, 12)
                .padding(.horizontal, 24)

            controlPanel
                .padding(.top, 16)
                .padding(.bottom, 8)
        }
    }

    /// Duration and chapter count, as the small pills beside the title.
    @ViewBuilder
    private var metaChips: some View {
        HStack(spacing: 9) {
            metaChip(audiobook.duration.hoursMinutesFormatted)
            if !chapters.isEmpty {
                metaChip(String(
                    format: NSLocalizedString("%d chapters", comment: "Number of chapters"),
                    chapters.count
                ))
            }
        }
    }

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .glassPill(height: 30)
    }

    /// Every chapter, the playing one marked and scrolled into view; the header link opens the
    /// full-screen list the phone uses.
    @ViewBuilder
    private var chapterTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(NSLocalizedString("Chapters", comment: "Chapter list sheet title"))
                    .font(.system(size: 20, weight: .bold))
                Text(chapterTally)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(NSLocalizedString("Show all", comment: "Player: open the full chapter list")) {
                    withHapticFeedback { showingChapterList = true }
                }
                .font(.system(size: 13.5, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
            .padding(.horizontal, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(chapters, id: \.id) { chapter in
                            ChapterRowView(chapter: chapter, isCurrent: chapter.id == currentChapter?.id) {
                                audioManager.seek(to: chapter.startTime)
                                audioManager.startPlayback()
                            }
                            .id(chapter.id)
                        }
                    }
                    .padding(6)
                }
                .onAppear {
                    guard let currentChapter else { return }
                    proxy.scrollTo(currentChapter.id, anchor: .center)
                }
            }
            .glassCard(cornerRadius: 20)
        }
        .frame(maxHeight: .infinity)
    }

    /// "13 listened · 29 left".
    private var chapterTally: String {
        let heard = currentChapter.flatMap { current in chapters.firstIndex { $0.id == current.id } } ?? 0
        return String(
            format: NSLocalizedString("%d listened · %d left", comment: "Player: chapters heard and remaining"),
            heard,
            chapters.count - heard
        )
    }
}
