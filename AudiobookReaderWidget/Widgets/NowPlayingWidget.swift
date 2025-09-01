import SwiftUI
import WidgetKit
import Intents

// MARK: - Now Playing Widget Entry
struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let audiobook: AudiobookInfo?
    let isPlaying: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval
    let coverImage: UIImage?
}

// MARK: - Audiobook Info for Widget
struct AudiobookInfo {
    let title: String
    let author: String
    let chapterTitle: String?
    let progress: Float
}

// MARK: - Now Playing Widget Provider
struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(
            date: Date(),
            audiobook: AudiobookInfo(
                title: "Sample Audiobook",
                author: "Sample Author",
                chapterTitle: "Chapter 1: Introduction",
                progress: 0.3
            ),
            isPlaying: true,
            currentTime: 900, // 15 minutes
            duration: 3600, // 1 hour
            coverImage: UIImage(systemName: "book.circle")
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        let entry = getCurrentPlaybackState()
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        let currentEntry = getCurrentPlaybackState()
        
        // Update timeline based on playback state
        let refreshDate = currentEntry.isPlaying ? 
            Date().addingTimeInterval(30) : // Update every 30 seconds when playing
            Date().addingTimeInterval(300)   // Update every 5 minutes when paused
        
        let timeline = Timeline(entries: [currentEntry], policy: .after(refreshDate))
        completion(timeline)
    }
    
    private func getCurrentPlaybackState() -> NowPlayingEntry {
        let shared = NowPlayingSharedStore.read()
        let title = shared.title ?? "Sample Audiobook"
        let author = shared.author ?? "Sample Author"
        let isPlaying = shared.isPlaying
        let current = shared.current
        let duration = max(shared.duration, 1)
        let progress = Float(min(max(current / duration, 0), 1))
        var coverImage: UIImage? = nil
        if let data = shared.cover { coverImage = UIImage(data: data) }

        let info = AudiobookInfo(title: title, author: author, chapterTitle: nil, progress: progress)
        return NowPlayingEntry(
            date: Date(),
            audiobook: info,
            isPlaying: isPlaying,
            currentTime: current,
            duration: duration,
            coverImage: coverImage
        )
    }
}

// MARK: - Now Playing Widget View
struct NowPlayingWidgetView: View {
    let entry: NowPlayingEntry
    @Environment(\.widgetFamily) var widgetFamily
    
    var body: some View {
        switch widgetFamily {
        case .systemSmall:
            SmallNowPlayingView(entry: entry)
        case .systemMedium:
            MediumNowPlayingView(entry: entry)
        case .systemLarge:
            LargeNowPlayingView(entry: entry)
        case .systemExtraLarge:
            ExtraLargeNowPlayingView(entry: entry)
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            SmallNowPlayingView(entry: entry)
        @unknown default:
            SmallNowPlayingView(entry: entry)
        }
    }
}

// MARK: - Small Widget View
struct SmallNowPlayingView: View {
    let entry: NowPlayingEntry
    
    var body: some View {
        ZStack {
            // Background with cover art
            if let coverImage = entry.coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .overlay {
                        LinearGradient(
                            colors: [Color.clear, Color.black.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.quaternary)
            }
            
            VStack(spacing: 4) {
                Spacer()
                
                // Play/Pause indicator
                Image(systemName: entry.isPlaying ? "play.fill" : "pause.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                
                // Title (truncated)
                if let audiobook = entry.audiobook {
                    Text(audiobook.title)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Medium Widget View
struct MediumNowPlayingView: View {
    let entry: NowPlayingEntry
    
    var body: some View {
        HStack(spacing: 12) {
            // Cover art
            if let coverImage = entry.coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(width: 60, height: 60)
                    .overlay {
                        Image(systemName: "book")
                            .foregroundColor(.secondary)
                    }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if let audiobook = entry.audiobook {
                    // Title
                    Text(audiobook.title)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    
                    // Author
                    Text(audiobook.author)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    // Progress bar
                    ProgressView(value: audiobook.progress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .scaleEffect(y: 0.5)
                    
                    // Time info
                    HStack {
                        Text(formatTime(entry.currentTime))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Image(systemName: entry.isPlaying ? "play.fill" : "pause.fill")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Large Widget View
struct LargeNowPlayingView: View {
    let entry: NowPlayingEntry
    
    var body: some View {
        VStack(spacing: 16) {
            // Cover art and info
            HStack(spacing: 16) {
                if let coverImage = entry.coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.quaternary)
                        .frame(width: 80, height: 80)
                        .overlay {
                            Image(systemName: "book")
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    if let audiobook = entry.audiobook {
                        Text(audiobook.title)
                            .font(.headline)
                            .lineLimit(2)
                            .foregroundColor(.primary)
                        
                        Text(audiobook.author)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        if let chapterTitle = audiobook.chapterTitle {
                            Text(chapterTitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                
                Spacer()
                
                // Playback status
                VStack {
                    Image(systemName: entry.isPlaying ? "play.fill" : "pause.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    
                    Text(entry.isPlaying ? "Playing" : "Paused")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Progress section
            if let audiobook = entry.audiobook {
                VStack(spacing: 8) {
                    ProgressView(value: audiobook.progress)
                        .progressViewStyle(LinearProgressViewStyle())
                    
                    HStack {
                        Text(formatTime(entry.currentTime))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(formatTime(entry.duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Extra Large Widget View
struct ExtraLargeNowPlayingView: View {
    let entry: NowPlayingEntry
    
    var body: some View {
        ZStack {
            // Background with cover art
            if let coverImage = entry.coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .overlay {
                        LinearGradient(
                            colors: [Color.clear, Color.black.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            } else {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.quaternary)
            }
            
            VStack(spacing: 20) {
                Spacer()
                
                // Content
                VStack(spacing: 16) {
                    if let audiobook = entry.audiobook {
                        // Title and author
                        VStack(spacing: 4) {
                            Text(audiobook.title)
                                .font(.title2.weight(.semibold))
                                .foregroundColor(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                            
                            Text(audiobook.author)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                                .lineLimit(1)
                        }
                        
                        // Chapter info
                        if let chapterTitle = audiobook.chapterTitle {
                            Text(chapterTitle)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        
                        // Progress
                        VStack(spacing: 8) {
                            ProgressView(value: audiobook.progress)
                                .progressViewStyle(LinearProgressViewStyle())
                                .tint(.white)
                            
                            HStack {
                                Text(formatTime(entry.currentTime))
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                                
                                Spacer()
                                
                                HStack(spacing: 4) {
                                    Image(systemName: entry.isPlaying ? "play.fill" : "pause.fill")
                                        .font(.caption)
                                    
                                    Text(entry.isPlaying ? "Playing" : "Paused")
                                        .font(.caption)
                                }
                                .foregroundColor(.white.opacity(0.8))
                                
                                Spacer()
                                
                                Text(formatTime(entry.duration))
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

// MARK: - Widget Configuration
struct NowPlayingWidget: Widget {
    let kind = "NowPlayingWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingProvider()) { entry in
            NowPlayingWidgetView(entry: entry)
                .containerBackground(.regularMaterial, for: .widget)
        }
        .configurationDisplayName("Now Playing")
        .description("See what's currently playing and control playback")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

// MARK: - Utility Functions
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

// MARK: - Widget Registration
// For iOS 26 - widgets need to be explicitly registered with the system
// This approach allows widgets to be discoverable in the dashboard when in main app target
extension AudiobookReaderApp {
    static func registerWidgets() {
        // Register widgets with the system
        WidgetCenter.shared.reloadAllTimelines()
    }
}
