import SwiftUI
import WatchKit

/// The player screen. Drives the local player when the audio is here, and the phone when it
/// is not — same layout either way, with a caption saying which.
struct WatchPlayerView: View {
    let book: AudiobookModel

    @State private var scrub: Double = 0
    @State private var isScrubbing = false
    @State private var showSpeed = false
    @State private var showSleep = false

    private var audio: WatchAudioManager { .shared }
    private var sync: PhoneSyncService { .shared }

    private var isLoaded: Bool { audio.currentBook?.id == book.id }
    /// The phone is the one making noise, so the transport talks to it.
    private var isRemote: Bool {
        sync.phoneNowPlaying?.bookID == book.id && !(isLoaded && audio.player.isPlaying)
    }

    private var elapsed: TimeInterval {
        if isScrubbing { return scrub }
        if isLoaded { return audio.player.currentTime }
        return sync.phoneNowPlaying?.position ?? book.currentPosition
    }

    private var duration: TimeInterval {
        isLoaded && audio.player.duration > 0 ? audio.player.duration : book.duration
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                header
                progress
                transport
                WatchPlayerChipsView(book: book, showSpeed: $showSpeed, showSleep: $showSleep)
                captions
            }
            .padding(.horizontal, 4)
        }
        .focusable()
        .digitalCrownRotation(
            detent: $scrub,
            from: 0,
            through: max(duration, 1),
            by: 15,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true,
            onChange: { _ in isScrubbing = true },
            onIdle: {
                guard isScrubbing else { return }
                isScrubbing = false
                commitScrub()
            }
        )
        .navigationTitle(Text(book.displayTitle))
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadIfPossible() }
        .sheet(isPresented: $showSpeed) { SpeedPickerView() }
        .sheet(isPresented: $showSleep) { SleepTimerPickerView() }
        .userActivity("io.jayet.Isora.listening", isActive: true) { activity in
            activity.userInfo = ["bookID": book.id.uuidString, "position": elapsed]
            activity.isEligibleForHandoff = true
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 8) {
            WatchCoverView(data: book.coverImageData, side: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(book.displayTitle)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                if let number = chapterNumber {
                    Text("\(String(localized: "Ch.")) \(number)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var progress: some View {
        VStack(spacing: 2) {
            ProgressView(value: min(max(elapsed, 0), max(duration, 1)), total: max(duration, 1))
                .tint(tint)
            HStack {
                Text(elapsed.clockFormatted)
                Spacer()
                Text("-\(max(duration - elapsed, 0).clockFormatted)")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    private var transport: some View {
        HStack(spacing: 12) {
            roundButton("gobackward.15", size: 38) { skip(-15) }
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .bold))
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(.plain)
            .background(tint.opacity(0.35), in: Circle())
            roundButton("goforward.15", size: 38) { skip(15) }
        }
    }

    @ViewBuilder
    private var captions: some View {
        if isRemote {
            caption(String(localized: "on iPhone"))
        }
        if audio.needsHeadphones {
            caption(String(localized: "Connect AirPods"))
        }
        if let waiting = audio.waitingForChapter {
            caption("\(String(localized: "Waiting for ch.")) \(waiting)")
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private func roundButton(_ system: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .background(.quaternary, in: Circle())
    }

    // MARK: - State

    private var isPlaying: Bool {
        isRemote ? (sync.phoneNowPlaying?.isPlaying ?? false) : (isLoaded && audio.player.isPlaying)
    }

    private var chapterNumber: Int? {
        book.chapter(at: elapsed).map { Int($0.chapterNumber) }
    }

    private var tint: Color {
        CoverTint.color(for: book.coverImageData) ?? .accentColor
    }

    // MARK: - Actions

    private func loadIfPossible() async {
        guard !isLoaded,
              !WatchTransferState.shared.readyChapters(bookID: book.id).isEmpty else { return }
        await audio.load(book)
        scrub = audio.player.currentTime
    }

    private func togglePlayback() {
        WKInterfaceDevice.current().play(.click)
        guard !isRemote else {
            sync.send(RemoteCommand.toggle)
            return
        }
        guard isLoaded else {
            Task { await audio.loadAndPlay(book) }
            return
        }
        audio.toggle()
    }

    private func skip(_ seconds: TimeInterval) {
        guard !isRemote else {
            sync.send(seconds > 0 ? .skipForward(seconds) : .skipBackward(-seconds))
            return
        }
        seconds > 0 ? audio.skipForward() : audio.skipBackward()
    }

    private func commitScrub() {
        guard !isRemote else {
            sync.send(RemoteCommand.seek(scrub))
            return
        }
        audio.seek(to: scrub)
    }
}
