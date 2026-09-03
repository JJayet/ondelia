import ActivityKit
import SwiftUI
import WidgetKit
import AppIntents
import Combine

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
