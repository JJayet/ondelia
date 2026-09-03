import SwiftUI

struct ChapterListView: View {
    let chapters: [ChapterModel]
    let onChapterTap: (ChapterModel) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(chapters, id: \.id) { chapter in
                    ChapterRowView(chapter: chapter) {
                        onChapterTap(chapter)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Chapters", comment: "Chapter list sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Done", comment: "Done button")) { dismiss() }
                }
            }
        }
    }
}

struct ChapterRowView: View {
    let chapter: ChapterModel
    let onTap: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.title ?? String(format: NSLocalizedString("Chapter %d", comment: "Default chapter title with number"), chapter.chapterNumber))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                
                Text(formatTime(chapter.startTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "play.fill")
                .font(.caption)
                .foregroundStyle(.blue)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle()) // Make entire area tappable
        .onTapGesture {
            Log.ui.debug("📖 Chapter tapped: \(chapter.title ?? "Chapter \(chapter.chapterNumber)") at \(formatTime(chapter.startTime))")
            onTap()
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
