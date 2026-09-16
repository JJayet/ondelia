import AppIntents
import SwiftUI
import WidgetKit

/// Play/pause from Control Center, the Lock Screen and the Action button.
///
/// The toggle reflects the snapshot the app writes to the shared app group, and its action
/// goes through the same `NowPlayingSharedStore` command channel the widget buttons already
/// use, so there is one path into playback rather than two.
struct PlaybackControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "io.jayet.Isora.playback-control",
            provider: PlaybackStateProvider()
        ) { state in
            ControlWidgetToggle(
                isOn: state.isPlaying,
                action: TogglePlaybackControlIntent()
            ) {
                // The title doubles as the accessibility label, so it names the book when
                // there is one rather than saying "Audiobook" to a screen reader.
                Label(
                    state.title ?? NSLocalizedString("Audiobook", comment: "Control widget fallback title"),
                    systemImage: state.isPlaying ? "pause.fill" : "play.fill"
                )
            } valueLabel: { isPlaying in
                Text(isPlaying
                     ? NSLocalizedString("Playing", comment: "Control widget state")
                     : NSLocalizedString("Paused", comment: "Control widget state"))
            }
        }
        .displayName("Play/Pause")
        .description("Toggle playback")
    }
}

/// What the control needs to render: whether audio is running, and what is playing.
struct PlaybackControlState {
    let isPlaying: Bool
    let title: String?
}

struct PlaybackStateProvider: ControlValueProvider {
    /// Shown in the controls gallery, where there is no live state to read.
    let previewValue = PlaybackControlState(isPlaying: false, title: nil)

    func currentValue() async throws -> PlaybackControlState {
        let snapshot = NowPlayingSharedStore.read()
        return PlaybackControlState(
            isPlaying: snapshot.isPlaying,
            title: snapshot.title?.isEmpty == false ? snapshot.title : nil
        )
    }
}

/// `SetValueIntent` is what a toggle control requires; `AudioPlaybackIntent` is what lets the
/// system start audio on our behalf when the app is not already running.
struct TogglePlaybackControlIntent: SetValueIntent, AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play/Pause"
    static let description = IntentDescription("Toggle playback")

    @Parameter(title: "Playing")
    var value: Bool

    func perform() async throws -> some IntentResult {
        // The app owns the player, so the command is queued and consumed there. `.toggle`
        // rather than `value` because the app's own state is the authority on what to do.
        NowPlayingSharedStore.send(.toggle)
        return .result()
    }
}
