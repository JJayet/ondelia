import SwiftUI

struct ChapterListView: View {
    let chapters: [ChapterModel]
    /// The chapter being heard, marked in the list and scrolled to when the sheet opens.
    let currentChapter: ChapterModel?
    let onChapterTap: (ChapterModel) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(chapters, id: \.id) { chapter in
                            ChapterRowView(chapter: chapter, isCurrent: chapter.id == currentChapter?.id) {
                                onChapterTap(chapter)
                            }
                            .id(chapter.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onAppear {
                    guard let currentChapter else { return }
                    proxy.scrollTo(currentChapter.id, anchor: .center)
                }
            }
            .background(TintedBackground(intensity: 0.55))
            .navigationTitle(NSLocalizedString("Chapters", comment: "Chapter list sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Done", comment: "Done button")) { dismiss() }
                }
            }
        }
    }
}

struct ChapterRowView: View {
    let chapter: ChapterModel
    var isCurrent = false
    let onTap: () -> Void

    private var title: String {
        chapter.title
            ?? String(
                format: NSLocalizedString("Chapter %d", comment: "Default chapter title with number"),
                chapter.chapterNumber
            )
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 13) {
                // The playing chapter trades its number for the design's three-bar meter.
                Group {
                    if isCurrent {
                        PlayingBars()
                    } else {
                        Text(verbatim: "\(chapter.chapterNumber)")
                            .font(.system(size: 12.5))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 26)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(chapter.startTime.clockFormatted)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 12)
            .background {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Three bars breathing at different rates — the "this one is playing" mark in the design.
private struct PlayingBars: View {
    @State private var animating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let heights: [(CGFloat, CGFloat, Double)] = [(4, 13, 0), (11, 5, 0.15), (7, 14, 0.3)]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, bar in
                Capsule()
                    .fill(.tint)
                    .frame(width: 2.5, height: animating ? bar.1 : bar.0)
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 0.45).repeatForever(autoreverses: true).delay(bar.2),
                        value: animating
                    )
            }
        }
        .frame(height: 14, alignment: .bottom)
        .onAppear { animating = true }
        .accessibilityHidden(true)
    }
}
