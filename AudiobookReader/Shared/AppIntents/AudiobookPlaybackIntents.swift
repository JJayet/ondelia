import AppIntents
import Foundation

// MARK: - App Intents for Controls
struct PlayPauseIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play/Pause"
    static let description = IntentDescription("Toggle playback")
    
    func perform() async throws -> some IntentResult {
        NowPlayingSharedStore.send(.toggle)
        return .result()
    }
}

struct SkipForwardIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Skip Forward"
    static let description = IntentDescription("Skip forward 15 seconds")
    
    func perform() async throws -> some IntentResult {
        NowPlayingSharedStore.send(.skipForward)
        return .result()
    }
}

struct SkipBackwardIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Skip Backward"  
    static let description = IntentDescription("Skip backward 15 seconds")
    
    func perform() async throws -> some IntentResult {
        NowPlayingSharedStore.send(.skipBackward)
        return .result()
    }
}
