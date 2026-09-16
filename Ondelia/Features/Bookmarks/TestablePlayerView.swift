import SwiftUI
import UIKit

/// A decoupled, testable player view that mirrors core player interactions
/// without relying on singletons or app-specific models.
///
/// Inject state via bindings and handle user actions with closures to make this
/// view easy to preview and test.
struct TestablePlayerView: View {
    // Display
    let title: String
    let author: String?
    let coverImage: UIImage?

    // Timeline
    @Binding var currentTime: TimeInterval
    let duration: TimeInterval

    // Playback
    @Binding var isPlaying: Bool
    @State private var isScrubbing: Bool = false

    // Rate / Sleep
    @Binding var playbackRate: Float
    let sleepTimeRemaining: TimeInterval?

    // Actions
    var onPlayPause: (() -> Void)?
    var onSkipBackward: (() -> Void)?
    var onSkipForward: (() -> Void)?
    var onSeekCommit: ((TimeInterval) -> Void)?
    var onChangeRate: ((Float) -> Void)?
    var onOpenBookmarks: (() -> Void)?
    var onOpenChapters: (() -> Void)?
    var onOpenTranscription: (() -> Void)?
    var onOpenQueue: (() -> Void)?

    init(
        title: String,
        author: String? = nil,
        coverImage: UIImage? = nil,
        currentTime: Binding<TimeInterval>,
        duration: TimeInterval,
        isPlaying: Binding<Bool>,
        playbackRate: Binding<Float>,
        sleepTimeRemaining: TimeInterval? = nil,
        onPlayPause: (() -> Void)? = nil,
        onSkipBackward: (() -> Void)? = nil,
        onSkipForward: (() -> Void)? = nil,
        onSeekCommit: ((TimeInterval) -> Void)? = nil,
        onChangeRate: ((Float) -> Void)? = nil,
        onOpenBookmarks: (() -> Void)? = nil,
        onOpenChapters: (() -> Void)? = nil,
        onOpenTranscription: (() -> Void)? = nil,
        onOpenQueue: (() -> Void)? = nil
    ) {
        self.title = title
        self.author = author
        self.coverImage = coverImage
        self._currentTime = currentTime
        self.duration = duration
        self._isPlaying = isPlaying
        self._playbackRate = playbackRate
        self.sleepTimeRemaining = sleepTimeRemaining
        self.onPlayPause = onPlayPause
        self.onSkipBackward = onSkipBackward
        self.onSkipForward = onSkipForward
        self.onSeekCommit = onSeekCommit
        self.onChangeRate = onChangeRate
        self.onOpenBookmarks = onOpenBookmarks
        self.onOpenChapters = onOpenChapters
        self.onOpenTranscription = onOpenTranscription
        self.onOpenQueue = onOpenQueue
    }

    var body: some View {
        VStack(spacing: 16) {
            // Artwork
            Group {
                if let image = coverImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 280, maxHeight: 280)
                        .cornerRadius(12)
                        .accessibilityIdentifier("player.cover")
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(maxWidth: 280, maxHeight: 280)
                        .overlay(
                            Image(systemName: "headphones")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                        )
                        .cornerRadius(12)
                        .accessibilityIdentifier("player.cover.placeholder")
                }
            }
            .frame(maxWidth: .infinity)

            // Title & author
            VStack(spacing: 4) {
                Text(title)
                    .font(.title2).bold()
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("player.title")
                if let author {
                    Text(author)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("player.author")
                }
            }
            .padding(.horizontal)

            // Timeline slider
            VStack(spacing: 6) {
                Slider(
                    value: Binding(
                        get: { currentTime },
                        set: { newValue in
                            currentTime = newValue
                        }
                    ),
                    in: 0...max(duration, 0.0001),
                    onEditingChanged: { editing in
                        isScrubbing = editing
                        if !editing {
                            onSeekCommit?(currentTime)
                        }
                    }
                )
                .accessibilityIdentifier("player.slider")

                HStack {
                    Text(formatTime(currentTime))
                        .font(.caption.monospacedDigit())
                        .accessibilityIdentifier("player.currentTime")
                    Spacer()
                    Text("-" + formatTime(max(duration - currentTime, 0)))
                        .font(.caption.monospacedDigit())
                        .accessibilityIdentifier("player.timeRemaining")
                }
                .padding(.horizontal)
            }

            // Transport controls
            HStack(spacing: 36) {
                Button(action: { onSkipBackward?() }) {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                }
                .accessibilityIdentifier("player.skipBackward")

                Button(action: {
                    isPlaying.toggle()
                    onPlayPause?()
                }) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 52))
                }
                .accessibilityIdentifier("player.playPause")

                Button(action: { onSkipForward?() }) {
                    Image(systemName: "goforward.30")
                        .font(.title2)
                }
                .accessibilityIdentifier("player.skipForward")
            }
            .padding(.top, 4)

            // Rate + Sleep
            HStack(spacing: 16) {
                Button(action: {
                    // Cycle common rates: 0.75, 1.0, 1.25, 1.5, 1.75, 2.0
                    let common: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
                    if let idx = common.firstIndex(where: { abs($0 - playbackRate) < 0.001 }) {
                        let next = common[(idx + 1) % common.count]
                        playbackRate = next
                        onChangeRate?(next)
                    } else {
                        playbackRate = 1.0
                        onChangeRate?(1.0)
                    }
                }) {
                    Text(String(format: "%.2fx", playbackRate))
                        .font(.callout.monospacedDigit())
                }
                .accessibilityIdentifier("player.rate")

                if let sleep = sleepTimeRemaining {
                    Label(formatTime(sleep), systemImage: "moon.fill")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("player.sleepRemaining")
                }
            }

            // Secondary actions
            HStack(spacing: 12) {
                Button("Bookmarks") { onOpenBookmarks?() }
                    .accessibilityIdentifier("player.openBookmarks")
                Button("Chapters") { onOpenChapters?() }
                    .accessibilityIdentifier("player.openChapters")
                Button("Transcript") { onOpenTranscription?() }
                    .accessibilityIdentifier("player.openTranscription")
                Button("Queue") { onOpenQueue?() }
                    .accessibilityIdentifier("player.openQueue")
            }
            .font(.footnote)
            .padding(.top, 8)
        }
        .padding()
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite && !t.isNaN else { return "--:--" }
        let total = Int(t.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

#Preview("TestablePlayerView") {
    // Local state for interactive preview
    struct PreviewHarness: View {
        @State var currentTime: TimeInterval = 75
        @State var duration: TimeInterval = 3600
        @State var isPlaying: Bool = true
        @State var rate: Float = 1.0

        var body: some View {
            TestablePlayerView(
                title: "The Example Book",
                author: "A. Author",
                coverImage: nil,
                currentTime: $currentTime,
                duration: duration,
                isPlaying: $isPlaying,
                playbackRate: $rate,
                sleepTimeRemaining: 1200,
                onPlayPause: { print("play/pause tapped") },
                onSkipBackward: { currentTime = max(currentTime - 15, 0) },
                onSkipForward: { currentTime = min(currentTime + 30, duration) },
                onSeekCommit: { newTime in currentTime = newTime },
                onChangeRate: { newRate in rate = newRate },
                onOpenBookmarks: { print("open bookmarks") },
                onOpenChapters: { print("open chapters") },
                onOpenTranscription: { print("open transcription") },
                onOpenQueue: { print("open queue") }
            )
            .frame(maxWidth: 420)
        }
    }
    return PreviewHarness()
}
