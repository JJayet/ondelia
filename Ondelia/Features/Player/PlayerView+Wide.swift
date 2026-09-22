import SwiftUI

extension PlayerView {
    // MARK: - Wide layout (design 6a / 6c)
    //
    // Regular width (iPad, Mac): cover and identity up top with the resume pill, the chapter
    // table filling the middle, and the transport docked across the bottom with the scrubber.
    @ViewBuilder
    var wideLayout: some View {
        VStack(spacing: 0) {
            wideTopBar

            HStack(alignment: .top, spacing: 32) {
                CoverArtView(audiobook: audiobook, size: 222, cornerRadius: 22)
                    .shadow(color: .black.opacity(0.45), radius: 24, y: 14)
                    .id(audiobook.id)

                VStack(alignment: .leading, spacing: 0) {
                    if let eyebrow {
                        Text(eyebrow.uppercased())
                            .font(.system(size: 11.5, weight: .semibold))
                            .tracking(1.8)
                            .foregroundStyle(.tint)
                            .padding(.bottom, 8)
                    }

                    Text(audiobook.title ?? AudiobookModel.unknownTitle)
                        .font(.system(size: 34, weight: .bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)

                    Text(credits)
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.top, 6)

                    metaChips.padding(.top, 16)

                    HStack(spacing: 11) {
                        resumePill
                        chipRow.frame(maxWidth: 380)
                    }
                    .padding(.top, 22)
                }
                .accessibilityElement(children: .contain)
            }
            .padding(.top, 6)
            .padding(.horizontal, 24)

            chapterTable
                .padding(.top, 28)
                .padding(.horizontal, 24)

            playerTips
                .padding(.top, 12)
                .padding(.horizontal, 24)

            if embedded {
                // The accessory bar below plays and skips; the scrubber is the one thing it
                // has no room for.
                ChapterScrubber(
                    position: currentTime,
                    duration: duration,
                    chapters: chapters,
                    onSeek: { audioManager.seek(to: $0) }
                )
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 12)
            } else {
                transportBar
                    .padding(.top, 16)
                    .padding(.bottom, 6)
            }
        }
    }

    // MARK: Top bar

    /// The breadcrumb only: "Series · Mistborn". Closing lives in the transport bar.
    @ViewBuilder
    private var wideTopBar: some View {
        HStack {
            if let collection = owningCollection {
                Text("\(collection.isSeries ? NSLocalizedString("Series", comment: "Collection kind: Hardcover series") : NSLocalizedString("Collections", comment: "Section title for collections")) · \(collection.name)")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 38)
        .padding(.top, 12)
        .padding(.horizontal, 24)
    }

    private var owningCollection: CollectionModel? {
        audiobookManager.collections.first { $0.bookIDs.contains(audiobook.id) }
    }

    /// "Mistborn · Volume 1" over the title, when the book belongs somewhere. Same rule as the
    /// collection screen: Hardcover's number in a series, the row's place in a hand-made
    /// collection, where Hardcover's number is from some other series.
    private var eyebrow: String? {
        guard let collection = owningCollection else { return nil }
        let number: Int? = collection.isSeries
            ? audiobook.hardcover?.seriesPosition.map { Int($0.rounded()) }
            : audiobookManager.orderedBooks(in: collection).firstIndex { $0.id == audiobook.id }.map { $0 + 1 }
        guard let number else { return collection.name }
        return "\(collection.name) · " + String(format: NSLocalizedString("Volume %d", comment: "Position in a series"), number)
    }

    // MARK: Identity

    @ViewBuilder
    private var metaChips: some View {
        HStack(spacing: 9) {
            metaChip(audiobook.duration.hoursMinutesFormatted)
            if !chapters.isEmpty {
                metaChip(String(format: NSLocalizedString("%d chapters", comment: "Number of chapters"), chapters.count))
            }
            // A playing book is on this device by definition; only the opposite is news.
            if !audiobookManager.hasFile(audiobook) {
                metaChip(NSLocalizedString("Not on this device", comment: "Missing audio badge"), dot: .secondary)
            }
        }
    }

    private func metaChip(_ text: String, dot: Color? = nil) -> some View {
        HStack(spacing: 7) {
            if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
            Text(text)
        }
        .foregroundStyle(.secondary)
        .glassPill(height: 30)
    }

    /// The accent pill: play/pause plus where the book is, "Chapter 14 · 17:22".
    private var resumePill: some View {
        Button {
            withHapticFeedback(.medium) {
                if audioManager.playbackState != .loading { audioManager.togglePlayback() }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                Text(positionLabel)
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(height: 44)
            .background(.tint, in: Capsule(style: .continuous))
            .shadow(color: themeManager.accentColor.color.opacity(0.35), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? NSLocalizedString("Pause", comment: "Pause playback") : NSLocalizedString("Play", comment: "Play playback"))
        .accessibilityValue(positionLabel)
    }

    /// "Chapter 14 · 17:22": the chapter and the position inside it.
    private var positionLabel: String {
        guard let chapter = currentChapter else { return currentTime.clockFormatted }
        return "\(chapterTitle(chapter)) · \((currentTime - chapter.startTime).clockFormatted)"
    }

    // MARK: Chapters

    private var currentChapterIndex: Int? {
        currentChapter.flatMap { current in chapters.firstIndex { $0.id == current.id } }
    }

    @ViewBuilder
    private var chapterTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(NSLocalizedString("Chapters", comment: "Chapter list sheet title"))
                    .font(.system(size: 20, weight: .bold))
                Text(chapterTally)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    // Not lazy: `scrollTo` needs the target row to exist, and a book has at
                    // most a few hundred chapters.
                    VStack(spacing: 0) {
                        ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                            WideChapterRow(
                                chapter: chapter,
                                title: chapterTitle(chapter),
                                state: rowState(index: index, chapter: chapter)
                            ) {
                                audioManager.seek(to: chapter.startTime)
                                audioManager.startPlayback()
                            }
                            .id(chapter.id)
                        }
                    }
                }
                // On change, not on appear: the position is still 0 when the screen opens,
                // so "current" is chapter 1 until the engine has loaded the book. This also
                // keeps the playing chapter in view as the book moves on.
                .onChange(of: currentChapter?.id, initial: true) { _, id in
                    guard let id else { return }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(80))
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
            .glassCard(cornerRadius: 20)
        }
        .frame(maxHeight: .infinity)
    }

    private func rowState(index: Int, chapter: ChapterModel) -> WideChapterRow.State {
        guard let current = currentChapterIndex else { return .upcoming }
        if index < current { return .heard }
        if index > current { return .upcoming }
        let span = max(chapter.endTime - chapter.startTime, 1)
        return .current(remaining: max(chapter.endTime - currentTime, 0), fraction: (currentTime - chapter.startTime) / span)
    }

    /// "13 listened · 29 left".
    private var chapterTally: String {
        let heard = currentChapterIndex ?? 0
        return String(
            format: NSLocalizedString("%d listened · %d left", comment: "Player: chapters heard and remaining"),
            heard,
            chapters.count - heard
        )
    }

    // MARK: Transport

    /// Docked across the bottom: the scrubber, then cover, chapter and times, the transport,
    /// and the way out.
    @ViewBuilder
    private var transportBar: some View {
        VStack(spacing: 14) {
            ChapterScrubber(
                position: currentTime,
                duration: duration,
                chapters: chapters,
                onSeek: { audioManager.seek(to: $0) }
            )

            HStack(spacing: 18) {
                CoverArtView(audiobook: audiobook, size: 50, cornerRadius: 10)

                VStack(alignment: .leading, spacing: 3) {
                    Text(currentChapter.map(chapterTitle) ?? (audiobook.title ?? AudiobookModel.unknownTitle))
                        .font(.system(size: 15.5, weight: .semibold))
                        .lineLimit(1)
                    Text(chapterTimes)
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .frame(width: 230, alignment: .leading)

                Spacer(minLength: 8)

                playbackControls(chapterSkips: false)
                    .frame(width: 300)

                Spacer(minLength: 8)

                Button {
                    withHapticFeedback { closePlayer() }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("Close Player", comment: "Close player accessibility label"))
                .accessibilityIdentifier(AccessibilityIdentifiers.Player.closeButton)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .glassCard(cornerRadius: 26)
    }

    /// "17:22 · -33:38": into the chapter, and left in it.
    private var chapterTimes: String {
        guard let chapter = currentChapter else { return currentTime.clockFormatted }
        let left = String(format: NSLocalizedString("-%@", comment: "Player: time remaining, negative clock format"), max(chapter.endTime - currentTime, 0).clockFormatted)
        return "\((currentTime - chapter.startTime).clockFormatted) · \(left)"
    }
}

/// One line of the wide chapter table: number or playing bars, title, "listened" or the
/// time left, the chapter's length; the playing row carries a hairline of its own progress.
struct WideChapterRow: View {
    enum State {
        case heard
        case current(remaining: TimeInterval, fraction: Double)
        case upcoming
    }

    let chapter: ChapterModel
    let title: String
    let state: State
    let onTap: () -> Void

    private var isCurrent: Bool { if case .current = state { return true }; return false }
    private var isHeard: Bool { if case .heard = state { return true }; return false }

    var body: some View {
        Button(action: { withHapticFeedback { onTap() } }) {
            HStack(spacing: 18) {
                Group {
                    if isCurrent {
                        PlayingBars()
                    } else {
                        Text(verbatim: "\(chapter.chapterNumber)")
                            .font(.system(size: 14.5))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 26)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isHeard ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                    if case .current(let remaining, _) = state {
                        Text(String(
                            format: NSLocalizedString("in progress · -%@", comment: "Chapter table: playing row, time left in the chapter"),
                            remaining.clockFormatted
                        ))
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(.tint)
                    }
                }

                Spacer(minLength: 8)

                if isHeard {
                    Text(NSLocalizedString("Listened", comment: "Chapter already heard"))
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }

                Text(max(chapter.endTime - chapter.startTime, 0).hoursMinutesFormatted)
                    .font(.system(size: 14.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 64, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .frame(height: isCurrent ? 64 : 58)
            .background { if isCurrent { Color.accentColor.opacity(0.1) } }
            .overlay(alignment: .bottom) {
                if case .current(_, let fraction) = state {
                    ProgressLine(value: fraction, height: 2)
                } else {
                    Rectangle().fill(.quaternary).frame(height: 0.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
