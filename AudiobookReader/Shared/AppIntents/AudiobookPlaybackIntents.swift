import ActivityKit
import AppIntents
import Combine
import Foundation

// MARK: - App Intents for Controls
struct PlayPauseIntent: AudioIntent {
    static var title: LocalizedStringResource = "Play/Pause"
    static var description = IntentDescription("Toggle playback")
    
    func perform() async throws -> some IntentResult {
        // Use the shared store to communicate with the main app
//        if let data = NowPlayingSharedStore.read() {
//            // Send notification to main app to toggle playback
//            NotificationCenter.default.post(name: .togglePlaybackFromWidget, object: nil)
//        }
        return .result()
    }
}

struct SkipForwardIntent: AudioIntent {
    static var title: LocalizedStringResource = "Skip Forward"
    static var description = IntentDescription("Skip forward 15 seconds")
    
    func perform() async throws -> some IntentResult {
        // Send notification to main app to skip forward
        NotificationCenter.default.post(name: .skipForwardFromWidget, object: nil)
        return .result()
    }
}

struct SkipBackwardIntent: AudioIntent {
    static var title: LocalizedStringResource = "Skip Backward"  
    static var description = IntentDescription("Skip backward 15 seconds")
    
    func perform() async throws -> some IntentResult {
        // Send notification to main app to skip backward
        NotificationCenter.default.post(name: .skipBackwardFromWidget, object: nil)
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

// MARK: - Notification Names
extension Notification.Name {
    static let togglePlaybackFromWidget = Notification.Name("togglePlaybackFromWidget")
    static let skipForwardFromWidget = Notification.Name("skipForwardFromWidget") 
    static let skipBackwardFromWidget = Notification.Name("skipBackwardFromWidget")
}
