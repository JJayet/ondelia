import SwiftUI
import WidgetKit
import AppIntents

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
                                .foregroundStyle(.secondary)
                        }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    if let audiobook = entry.audiobook {
                        Text(audiobook.title)
                            .font(.headline)
                            .lineLimit(2)
                            .foregroundStyle(.primary)
                        
                        Text(audiobook.author)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        
                        if let chapterTitle = audiobook.chapterTitle {
                            Text(chapterTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                
                Spacer()
                
                // Playback status
                VStack {
                    Button(intent: PlayPauseIntent()) {
                        Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundStyle(.tint)
                    }
                    Text(entry.isPlaying ? "Playing" : "Paused")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Progress section
            if let audiobook = entry.audiobook {
                VStack(spacing: 8) {
                    ProgressView(value: audiobook.progress)
                        .progressViewStyle(.linear)
                    
                    HStack {
                        Text(entry.currentTime.clockFormatted)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text(entry.duration.clockFormatted)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                            
                            Text(audiobook.author)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                        }
                        
                        // Chapter info
                        if let chapterTitle = audiobook.chapterTitle {
                            Text(chapterTitle)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        
                        // Progress
                        VStack(spacing: 8) {
                            ProgressView(value: audiobook.progress)
                                .progressViewStyle(.linear)
                                .tint(.white)
                            
                            HStack {
                                Text(entry.currentTime.clockFormatted)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.8))
                                
                                Spacer()
                                
                                HStack(spacing: 4) {
                                    Image(systemName: entry.isPlaying ? "play.fill" : "pause.fill")
                                        .font(.caption)
                                    
                                    Text(entry.isPlaying ? "Playing" : "Paused")
                                        .font(.caption)
                                }
                                .foregroundStyle(.white.opacity(0.8))
                                
                                Spacer()
                                
                                Text(entry.duration.clockFormatted)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.8))
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
