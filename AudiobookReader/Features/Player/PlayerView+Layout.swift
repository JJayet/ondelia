import SwiftUI
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
            PlayerBackdrop(audiobook: audiobook)

            VStack(spacing: 0) {
                headerControls

                titleBlock.padding(.top, 18)

                Spacer(minLength: 16)

                controlPanel

                chipRow.padding(.top, 12)

                upNextSection.padding(.top, 22)

                Spacer(minLength: 16)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Header
    @ViewBuilder
    var headerControls: some View {
        HStack {
            Button {
                // Dismiss overlay by clearing router's presented
                if let router = playerRouter {
                    router.presented = nil
                } else {
                    dismiss()
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
                showingChapterList = true
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

            Button {
                showingSleepTimer = true
            } label: {
                Image(systemName: sleepTimeRemaining > 0 ? "moon.fill" : "moon")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(sleepTimeRemaining > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .frame(width: 38, height: 38)
                    .glassEffect(.regular, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("Sleep Timer", comment: "Sleep timer accessibility label"))
            .accessibilityIdentifier(AccessibilityIdentifiers.Player.sleepTimerButton)
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 14)

            ChapterScrubber(
                position: currentTime,
                range: scrubberRange,
                remainingLabel: remainingLabel,
                onToggleRemaining: { showRemainingTime.toggle() },
                onSeek: { audioManager.seek(to: $0) }
            )

            playbackControls.padding(.top, 22)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .glassCard(cornerRadius: 34)
    }

    /// The chapter the scrubber spans, falling back to the whole book.
    var scrubberRange: ClosedRange<TimeInterval> {
        guard let chapter = currentChapter, chapter.endTime > chapter.startTime else {
            return 0...max(duration, 1)
        }
        return chapter.startTime...chapter.endTime
    }

    /// What is left of the chapter, or — tapped — what is left of the book.
    var remainingLabel: String {
        let left = showRemainingTime
            ? max(duration - currentTime, 0)
            : max(scrubberRange.upperBound - currentTime, 0)
        return String(
            format: showRemainingTime
                ? NSLocalizedString("%@ left in the book", comment: "Player: time left in the book")
                : NSLocalizedString("%@ left", comment: "Player: time left in the chapter"),
            left.clockFormatted
        )
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
