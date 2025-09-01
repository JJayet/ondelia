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
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
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
                Text(chapter.title ?? "Chapter \(chapter.chapterNumber)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(formatTime(chapter.startTime))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "play.fill")
                .font(.caption)
                .foregroundColor(.blue)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle()) // Make entire area tappable
        .onTapGesture {
            print("📖 Chapter tapped: \(chapter.title ?? "Chapter \(chapter.chapterNumber)") at \(formatTime(chapter.startTime))")
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
