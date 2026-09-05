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
        let current = getCurrentPlaybackState()

        // A paused book never moves, so one entry covers it. A playing one is projected forward
        // instead of asking for a reload every 30s: WidgetKit grants a handful of refreshes an
        // hour, and burning them on a progress bar meant the widget went stale mid-chapter.
        guard current.isPlaying else {
            completion(Timeline(entries: [current], policy: .after(Date().addingTimeInterval(300))))
            return
        }

        let rate = Double(NowPlayingSharedStore.read().playbackRate)
        let step: TimeInterval = 30
        let entries = (0..<60).map { index -> NowPlayingEntry in
            let offset = step * Double(index)
            return NowPlayingEntry(
                date: current.date.addingTimeInterval(offset),
                audiobook: current.audiobook.map {
                    AudiobookInfo(
                        title: $0.title,
                        author: $0.author,
                        chapterTitle: $0.chapterTitle,
                        progress: Float(min(max((current.currentTime + offset * rate) / current.duration, 0), 1))
                    )
                },
                isPlaying: true,
                currentTime: min(current.currentTime + offset * rate, current.duration),
                duration: current.duration,
                coverImage: current.coverImage
            )
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
    
    private func getCurrentPlaybackState() -> NowPlayingEntry {
        let shared = NowPlayingSharedStore.read()
        let isPlaying = shared.isPlaying
        let current = shared.current
        let duration = max(shared.duration, 1)
        let progress = Float(min(max(current / duration, 0), 1))
        var coverImage: UIImage? = nil
        if let data = shared.cover { coverImage = UIImage(data: data) }

        // No title in the shared store means nothing has been played yet. The placeholder
        // strings belong in `placeholder(in:)`, not on a real home screen.
        let info = shared.title.map {
            AudiobookInfo(
                title: $0,
                author: shared.author ?? "",
                chapterTitle: nil,
                progress: progress
            )
        }
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

// MARK: - Utility Functions
