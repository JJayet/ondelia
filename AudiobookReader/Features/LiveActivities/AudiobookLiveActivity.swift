import ActivityKit
import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Live Activity Attributes
struct AudiobookLiveActivityAttributes: ActivityAttributes {
    public typealias AudiobookStatus = ContentState
    
    public struct ContentState: Codable, Hashable {
        var title: String
        var author: String
        var chapterTitle: String?
        var currentTime: TimeInterval
        var duration: TimeInterval
        var isPlaying: Bool
        var playbackRate: Float
        var coverImageData: Data?
        
        var progress: Double {
            guard duration > 0 else { return 0 }
            return currentTime / duration
        }
        
        var formattedCurrentTime: String {
            return formatTime(currentTime)
        }
        
        var formattedDuration: String {
            return formatTime(duration)
        }
        
        var remainingTime: TimeInterval {
            return duration - currentTime
        }
        
        var formattedRemainingTime: String {
            return formatTime(remainingTime)
        }
    }
    
    var audiobookId: String
    var startTime: Date
}

// MARK: - Live Activity Widget
struct AudiobookLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AudiobookLiveActivityAttributes.self) { context in
            // Lock screen/banner UI goes here
            AudiobookLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here  
                DynamicIslandExpandedRegion(.leading) {
                    AudiobookCompactLeadingView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    AudiobookCompactTrailingView(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    AudiobookExpandedView(context: context)
                }
            } compactLeading: {
                // Compact leading view
                AudiobookCompactLeadingView(context: context)
            } compactTrailing: {
                // Compact trailing view  
                AudiobookCompactTrailingView(context: context)
            } minimal: {
                // Minimal view when multiple activities
                AudiobookMinimalView(context: context)
            }
            .widgetURL(URL(string: "audiobookreader://player"))
            .keylineTint(Color.accentColor)
        }
    }
}

// MARK: - Lock Screen View
struct AudiobookLiveActivityView: View {
    let context: ActivityViewContext<AudiobookLiveActivityAttributes>
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Cover art
                if let coverImageData = context.state.coverImageData,
                   let coverImage = UIImage(data: coverImageData) {
                    Image(uiImage: coverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                        .frame(width: 50, height: 50)
                        .overlay {
                            Image(systemName: "book.fill")
                                .foregroundColor(.secondary)
                        }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.title)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Text(context.state.author)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    if let chapterTitle = context.state.chapterTitle {
                        Text(chapterTitle)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                VStack(spacing: 4) {
                    Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    
                    if context.state.playbackRate != 1.0 {
                        Text("\(String(format: "%.1fx", context.state.playbackRate))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Progress bar with time
            VStack(spacing: 6) {
                ProgressView(value: context.state.progress)
                    .progressViewStyle(LinearProgressViewStyle())
                    .tint(.accentColor)
                
                HStack {
                    Text(context.state.formattedCurrentTime)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if context.state.isPlaying {
                        Text("-\(context.state.formattedRemainingTime)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text(context.state.formattedDuration)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Dynamic Island Expanded View
struct AudiobookExpandedView: View {
    let context: ActivityViewContext<AudiobookLiveActivityAttributes>
    
    var body: some View {
        VStack(spacing: 16) {
            // Top section with cover and info
            HStack(spacing: 12) {
                if let coverImageData = context.state.coverImageData,
                   let coverImage = UIImage(data: coverImageData) {
                    Image(uiImage: coverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.quaternary)
                        .frame(width: 60, height: 60)
                        .overlay {
                            Image(systemName: "book.fill")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.title)
                        .font(.headline)
                        .lineLimit(2)
                    
                    Text(context.state.author)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    if let chapterTitle = context.state.chapterTitle {
                        Text(chapterTitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
            }
            
            // Progress and controls
            VStack(spacing: 8) {
                HStack {
                    Text(context.state.formattedCurrentTime)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(context.state.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                ProgressView(value: context.state.progress)
                    .progressViewStyle(LinearProgressViewStyle())
                    .tint(.accentColor)
                
                // Playback controls
                HStack(spacing: 24) {
                    Button(intent: SkipBackwardIntent()) {
                        Image(systemName: "gobackward.15")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    
                    Button(intent: PlayPauseIntent()) {
                        Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    
                    Button(intent: SkipForwardIntent()) {
                        Image(systemName: "goforward.30")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    
                    if context.state.playbackRate != 1.0 {
                        Text("\(String(format: "%.1fx", context.state.playbackRate))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Compact Views
struct AudiobookCompactLeadingView: View {
    let context: ActivityViewContext<AudiobookLiveActivityAttributes>
    
    var body: some View {
        if let coverImageData = context.state.coverImageData,
           let coverImage = UIImage(data: coverImageData) {
            Image(uiImage: coverImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(Circle())
        } else {
            Image(systemName: "book.fill")
                .foregroundColor(.accentColor)
        }
    }
}

struct AudiobookCompactTrailingView: View {
    let context: ActivityViewContext<AudiobookLiveActivityAttributes>
    
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                .font(.caption)
                .foregroundColor(.accentColor)
            
            // Progress indicator
            ProgressView(value: context.state.progress)
                .progressViewStyle(LinearProgressViewStyle())
                .tint(.accentColor)
                .scaleEffect(x: 1, y: 0.5)
        }
    }
}

struct AudiobookMinimalView: View {
    let context: ActivityViewContext<AudiobookLiveActivityAttributes>
    
    var body: some View {
        Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
            .foregroundColor(.accentColor)
    }
}

// MARK: - App Intents for Controls
struct PlayPauseIntent: AudioIntent {
    static var title: LocalizedStringResource = "Play/Pause"
    static var description = IntentDescription("Toggle playback")
    
    func perform() async throws -> some IntentResult {
        // This would trigger the play/pause action in the app
        // Implementation depends on app architecture
        return .result()
    }
}

struct SkipForwardIntent: AudioIntent {
    static var title: LocalizedStringResource = "Skip Forward"
    static var description = IntentDescription("Skip forward 30 seconds")
    
    func perform() async throws -> some IntentResult {
        // This would trigger skip forward in the app
        return .result()
    }
}

struct SkipBackwardIntent: AudioIntent {
    static var title: LocalizedStringResource = "Skip Backward"  
    static var description = IntentDescription("Skip backward 15 seconds")
    
    func perform() async throws -> some IntentResult {
        // This would trigger skip backward in the app
        return .result()
    }
}

// MARK: - Base Audio Intent
protocol AudioIntent: AppIntent {
    // Common properties for audio intents
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

// MARK: - Live Activity Manager
class LiveActivityManager: ObservableObject {
    private var currentActivity: Activity<AudiobookLiveActivityAttributes>?
    
    func startLiveActivity(for audiobook: AudiobookLiveActivityAttributes.ContentState, audiobookId: String) {
        let attributes = AudiobookLiveActivityAttributes(
            audiobookId: audiobookId,
            startTime: Date()
        )
        
        do {
            currentActivity = try Activity<AudiobookLiveActivityAttributes>.request(
                attributes: attributes,
                content: ActivityContent(state: audiobook, staleDate: nil),
                pushType: nil
            )
            print("✨ Live Activity started successfully")
        } catch {
            print("❌ Failed to start Live Activity: \(error)")
        }
    }
    
    func updateLiveActivity(with newState: AudiobookLiveActivityAttributes.ContentState) {
        Task {
            guard let activity = currentActivity else { return }
            
            await activity.update(ActivityContent(state: newState, staleDate: nil))
            print("🔄 Live Activity updated")
        }
    }
    
    func endLiveActivity() {
        Task {
            guard let activity = currentActivity else { return }
            
            await activity.end(activity.content, dismissalPolicy: .immediate)
            currentActivity = nil
            print("🛑 Live Activity ended")
        }
    }
}
