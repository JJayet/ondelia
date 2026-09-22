import SwiftUI
import TipKit
import UIKit

extension PlayerView {
    // MARK: - Full Player View
    //
    // The ambience layout: the cover is the room the screen sits in rather than an object on
    // it, the title carries the top half, and everything you can touch lives in one glass
    // panel — chapter, waveform, transport — with the chips under it.
    @ViewBuilder
    func fullPlayerView(geometry: GeometryProxy) -> some View {
        ZStack {
            // Keyed on the book: rolling into the next one cross-fades the backdrop instead of
            // swapping it in one frame. The rest of the screen redraws in place under the same
            // animation, so title and rows settle rather than jump.
            PlayerBackdrop(audiobook: audiobook)
                .id(audiobook.id)
                .transition(.opacity)

            VStack(spacing: 0) {
                headerControls

                if horizontalSizeClass == .regular {
                    // Wide window (iPad, Mac, iPhone Duo open): see PlayerView+Wide.swift.
                    wideLayout
                } else {
                    titleBlock.padding(.top, 18)

                    Spacer(minLength: 16)

                    controlColumn

                    Spacer(minLength: 16)
                }
            }
            .padding(.horizontal, 16)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: audiobook.id)
    }

    /// Everything you can touch, stacked: panel, chips, tips, up next.
    var controlColumn: some View {
        VStack(spacing: 0) {
            controlPanel

            chipRow.padding(.top, 12)

            playerTips.padding(.top, 12)

            upNextSection.padding(.top, 22)
        }
    }

    // MARK: - Tips
    //
    // Inline, not popovers: a popover anchored on a chip sat on top of it and ate its taps.
    // TipKit shows at most one of these at a time, so the slot never stacks.
    @ViewBuilder
    var playerTips: some View {
        TipView(ChaptersTip())
        TipView(SleepTimerTip())
        TipView(TranscriptTip())
        TipView(QueueTip())
    }

    // MARK: - Header
    @ViewBuilder
    var headerControls: some View {
        HStack {
            Button {
                // Dismiss overlay by clearing router's presented
                if let router = playerRouter {
                    withHapticFeedback { router.presented = nil }
                } else {
                    withHapticFeedback { dismiss() }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .glassEffect(.regular, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("Close Player", comment: "Close player accessibility label"))
            .accessibilityIdentifier(AccessibilityIdentifiers.Player.closeButton)

            Spacer()

            // The chapter counter doubles as the way into the chapter list: the design has no
            // separate chapters button on this screen.
            Button {
                withHapticFeedback { showingChapterList = true }
            } label: {
                Text(chapterCounter)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(chapters.isEmpty)
            .accessibilityLabel(NSLocalizedString("Chapters", comment: "Chapter list sheet title"))
            .accessibilityIdentifier(AccessibilityIdentifiers.Player.chaptersButton)

            Spacer()

            // Balances the close button so the counter stays centred; the sleep timer lives in
            // the chip row alone now.
            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.top, 12)
    }

    /// "CHAPTER 14 / 42", or the book's own name when it has no chapters to count.
    var chapterCounter: String {
        guard let chapter = currentChapter, !chapters.isEmpty else {
            return NSLocalizedString("Now Playing", comment: "Player header label").uppercased()
        }
        let index = (chapters.firstIndex { $0.id == chapter.id } ?? 0) + 1
        return String(
            format: NSLocalizedString("Chapter %d / %d", comment: "Player header: chapter counter"),
            index,
            chapters.count
        ).uppercased()
    }

    // MARK: - Title
    @ViewBuilder
    var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(audiobook.title ?? AudiobookModel.unknownTitle)
                .font(.system(size: 32, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.6)

            Text(credits)
                .font(.system(size: 14.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityIdentifiers.Player.coverArt)
    }

    /// "Author · narrated by X", collapsed to the author alone when there is no narrator.
    var credits: String {
        let author = audiobook.author ?? AudiobookModel.unknownAuthor
        guard let narrator = audiobook.narrator else { return author }
        return String(
            format: NSLocalizedString("%@ · narrated by %@", comment: "Author and narrator credit"),
            author,
            narrator
        )
    }

    // MARK: - Control panel
    @ViewBuilder
    var controlPanel: some View {
        VStack(spacing: 0) {
            Text(currentChapter.map(chapterTitle) ?? (audiobook.title ?? AudiobookModel.unknownTitle))
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 14)

            ChapterScrubber(
                position: currentTime,
                duration: duration,
                chapters: chapters,
                onSeek: { audioManager.seek(to: $0) }
            )

            playbackControls.padding(.top, 22)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .glassCard(cornerRadius: 34)
    }

    func chapterTitle(_ chapter: ChapterModel) -> String {
        chapter.title
            ?? String(
                format: NSLocalizedString("Chapter %d", comment: "Default chapter title with number"),
                chapter.chapterNumber
            )
    }
}

// MARK: - Backdrop

/// The cover, blown up and blurred into the room the player sits in. Books with no artwork fall
/// back to the tint canvas the rest of the app uses.
struct PlayerBackdrop: View {
    let audiobook: AudiobookModel

    var body: some View {
        ZStack {
            TintedBackground(tint: CoverTintCache.tint(for: audiobook), intensity: 1.2)

            if let cover = CoverImageCache.image(for: audiobook) {
                GeometryReader { geometry in
                    Image(uiImage: cover)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        // Blurred past the edges: a 70pt blur samples transparency at the
                        // border and would draw a dark rim without the overscan.
                        .scaleEffect(1.2)
                        .blur(radius: 70, opaque: false)
                        .opacity(0.85)
                        .clipped()
                }
                .ignoresSafeArea()

                LinearGradient(
                    colors: [.black.opacity(0.1), .black.opacity(0.4), .black.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        }
        .accessibilityHidden(true)
    }
}
