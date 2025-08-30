import SwiftUI

// MARK: - Example Component Using Dependency Injection
struct BookInfoView: View {
    let audiobook: Audiobook
    @Environment(\.dependencies) private var deps
    
    // Access dependencies through the container
    private var audioManager: any AudioManagerProtocol { deps.audioManager }
    private var themeManager: any ThemeManagerProtocol { deps.themeManager }
    
    var body: some View {
        VStack(spacing: 12) {
            // Cover Image
            if let coverImageData = audiobook.coverImageData,
               let coverImage = UIImage(data: coverImageData) {
                Image(uiImage: coverImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 8)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(themeManager.accentColor.color.opacity(0.3))
                    .frame(width: 120, height: 120)
                    .overlay {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 40))
                            .foregroundColor(themeManager.accentColor.color)
                    }
            }
            
            // Book Details
            VStack(spacing: 6) {
                Text(audiobook.title ?? "Unknown Title")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                Text(audiobook.author ?? "Unknown Author")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if let narrator = audiobook.narrator {
                    Text("Narrated by \(narrator)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            // Playback Status
            HStack(spacing: 8) {
                Image(systemName: audioManager.playbackState == .playing ? "play.fill" : "pause.fill")
                    .foregroundColor(themeManager.accentColor.color)
                
                Text(formatPlaybackStatus())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Progress Bar
            ProgressView(value: progressValue)
                .progressViewStyle(LinearProgressViewStyle(tint: themeManager.accentColor.color))
                .scaleEffect(y: 0.5)
        }
        .padding()
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
    }
    
    private var progressValue: Double {
        let duration = audioManager.getDuration()
        let currentTime = audioManager.getCurrentTime()
        return duration > 0 ? currentTime / duration : 0
    }
    
    private func formatPlaybackStatus() -> String {
        let current = formatTime(audioManager.getCurrentTime())
        let total = formatTime(audioManager.getDuration())
        let progress = Int(progressValue * 100)
        return "\(current) / \(total) (\(progress)%)"
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

// MARK: - Modern SwiftUI Previews with Full Functionality
#Preview("Playing State") {
    BookInfoView(audiobook: PreviewContent.audiobook())
        .previewWithMockAudio(
            state: .playing,
            currentTime: 450.0,
            duration: 3600.0
        )
}

#Preview("Paused State") {
    BookInfoView(audiobook: PreviewContent.audiobook())
        .previewWithMockAudio(
            state: .paused,
            currentTime: 1800.0,
            duration: 3600.0
        )
}

#Preview("Long Title") {
    BookInfoView(audiobook: PreviewContent.audiobookLong())
        .previewWithMockAudio(
            state: .playing,
            currentTime: 3780.0,
            duration: 12600.0
        )
}

#Preview("Book Info - Different Themes") {
    Group {
        BookInfoView(audiobook: PreviewContent.audiobook())
            .previewWithTheme(theme: .light, accentColor: .blue)
        
        BookInfoView(audiobook: PreviewContent.audiobook())
            .previewWithTheme(theme: .dark, accentColor: .purple)
        
        BookInfoView(audiobook: PreviewContent.audiobook())
            .previewWithTheme(theme: .dark, accentColor: .green)
    }
}

#Preview("Book Info - All States") {
    VStack(spacing: 20) {
        BookInfoView(audiobook: PreviewContent.audiobook())
            .previewWithMockAudio(state: .playing)
        
        BookInfoView(audiobook: PreviewContent.audiobook())
            .previewWithMockAudio(state: .paused)
        
        BookInfoView(audiobook: PreviewContent.audiobook())
            .previewWithMockAudio(state: .loading)
    }
    .padding()
}

// MARK: - Advanced Preview Configuration Example
#Preview("Custom Configuration") {
    let config = PreviewStateConfigurator()
        .configurePlaybackState(.playing)
        .configureCurrentTime(2700.0) // 45 minutes
        .configureDuration(7200.0)    // 2 hours
        .configureTheme(.dark)
        .configureAccentColor(.orange)
        .build()
    
    return BookInfoView(audiobook: PreviewContent.audiobook(
        title: "Advanced SwiftUI Patterns",
        author: "iOS Developer",
        narrator: "Expert Reader"
    ))
    .environment(\.dependencies, config)
}