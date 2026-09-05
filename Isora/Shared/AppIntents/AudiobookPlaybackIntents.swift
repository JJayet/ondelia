import AppIntents
import Foundation

// MARK: - App Intents for Controls
//
// `AudioPlaybackIntent` is performed in the app process, cold-launching it when necessary —
// that is the whole point of the conformance. The type is compiled into the widget extension
// too, only so the widget can name it in `Button(intent:)`; that copy never runs the work, and
// it cannot, since the audio engine and the store do not exist there.

private func run(_ command: PlaybackCommand) async {
    #if WIDGET_EXTENSION
    NowPlayingSharedStore.send(command)
    #else
    await PlaybackCommands.perform(command)
    #endif
}

struct PlayPauseIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play/Pause"
    static let description = IntentDescription("Toggle playback")
    
    func perform() async throws -> some IntentResult {
        await run(.toggle)
        return .result()
    }
}

struct SkipForwardIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Skip Forward"
    static let description = IntentDescription("Skip forward")
    
    func perform() async throws -> some IntentResult {
        await run(.skipForward)
        return .result()
    }
}

struct SkipBackwardIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Skip Backward"  
    static let description = IntentDescription("Skip backward")
    
    func perform() async throws -> some IntentResult {
        await run(.skipBackward)
        return .result()
    }
}
