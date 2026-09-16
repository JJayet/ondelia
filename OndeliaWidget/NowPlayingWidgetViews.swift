import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Now Playing Widget View
struct NowPlayingWidgetView: View {
    let entry: NowPlayingEntry
    @Environment(\.widgetFamily) var widgetFamily
    
    var body: some View {
        if entry.audiobook == nil {
            NothingPlayingView()
        } else {
            playerView
        }
    }

    @ViewBuilder
    private var playerView: some View {
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
        case .systemExtraLargePortrait:
            ExtraLargeNowPlayingView(entry: entry)
        @unknown default:
            SmallNowPlayingView(entry: entry)
        }
    }
}

/// Shown until something has actually been played. The placeholder book belongs in Xcode's
/// gallery preview, not on a home screen.
struct NothingPlayingView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "book.closed")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Nothing playing")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                
                // Play/Pause control
                Button(intent: PlayPauseIntent()) {
                    Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                
                // Title (truncated)
                if let audiobook = entry.audiobook {
                    Text(audiobook.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
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
                            .foregroundStyle(.secondary)
                    }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if let audiobook = entry.audiobook {
                    // Title
                    Text(audiobook.title)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    
                    // Author
                    Text(audiobook.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    // Progress bar
                    ProgressView(value: audiobook.progress)
                        .progressViewStyle(.linear)
                        .scaleEffect(y: 0.5)
                    
                    // Time info
                    HStack {
                        Text(entry.currentTime.clockFormatted)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Button(intent: PlayPauseIntent()) {
                            Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
                                .font(.caption)
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
