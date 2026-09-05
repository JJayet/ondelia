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
                List {
                    ForEach(chapters, id: \.id) { chapter in
                        ChapterRowView(chapter: chapter, isCurrent: chapter.id == currentChapter?.id) {
                            onChapterTap(chapter)
                        }
                        .id(chapter.id)
                    }
                }
                .onAppear {
                    guard let currentChapter else { return }
                    proxy.scrollTo(currentChapter.id, anchor: .center)
                }
            }
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
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.title ?? String(format: NSLocalizedString("Chapter %d", comment: "Default chapter title with number"), chapter.chapterNumber))
                    .font(.subheadline)
                    .fontWeight(isCurrent ? .bold : .medium)
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                
                Text(chapter.startTime.clockFormatted)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: isCurrent ? "speaker.wave.2.fill" : "play.fill")
                .font(.caption)
                .foregroundStyle(.tint)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle()) // Make entire area tappable
        .onTapGesture {
            Log.ui.debug("📖 Chapter tapped: \(chapter.title ?? "Chapter \(chapter.chapterNumber)") at \(chapter.startTime.clockFormatted)")
            onTap()
        }
    }
    
}
