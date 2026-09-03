import SwiftUI
import WidgetKit
import Intents
import AppIntents

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
                title: String(localized: "Sample Audiobook"),
                author: String(localized: "Sample Author"),
                chapterTitle: String(localized: "Chapter 1: Introduction"),
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
        let title = shared.title ?? String(localized: "Sample Audiobook")
        let author = shared.author ?? String(localized: "Sample Author")
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

// MARK: - Widget Registration
// For iOS 26 - widgets need to be explicitly registered with the system
// This approach allows widgets to be discoverable in the dashboard when in main app target
extension AudiobookWidgetBundle {
    static func registerWidgets() {
        // Register widgets with the system
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Utility Functions
func formatTime(_ time: TimeInterval) -> String {
    let hours = Int(time) / 3600
    let minutes = (Int(time) % 3600) / 60
    let seconds = Int(time) % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
        return String(format: "%d:%02d", minutes, seconds)
    }
}
