import ActivityKit
import AppIntents
import Combine
import Foundation

// MARK: - App Intents for Controls
struct PlayPauseIntent: AudioIntent, AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play/Pause"
    static var description = IntentDescription("Toggle playback")
    
    func perform() async throws -> some IntentResult {
        NowPlayingSharedStore.send(.toggle)
        return .result()
    }
}

struct SkipForwardIntent: AudioIntent, AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Skip Forward"
    static var description = IntentDescription("Skip forward 15 seconds")
    
    func perform() async throws -> some IntentResult {
        NowPlayingSharedStore.send(.skipForward)
        return .result()
    }
}

struct SkipBackwardIntent: AudioIntent, AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Skip Backward"  
    static var description = IntentDescription("Skip backward 15 seconds")
    
    func perform() async throws -> some IntentResult {
        NowPlayingSharedStore.send(.skipBackward)
        return .result()
    }
}

// MARK: - Base Audio Intent
protocol AudioIntent: AppIntent {
    // Common properties for audio intents
}

// MARK: - Live Activity Manager
class LiveActivityManager: ObservableObject {
    private var currentActivity: Activity<AudiobookLiveActivityAttributes>?
    
    var isActivityActive: Bool {
        return currentActivity?.activityState == .active
    }
    
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
