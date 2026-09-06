import SwiftUI
import WatchKit

/// The three chips under the transport: speed, sleep timer, bookmark.
struct WatchPlayerChipsView: View {
    let book: AudiobookModel
    @Binding var showSpeed: Bool
    @Binding var showSleep: Bool

    private var audio: WatchAudioManager { .shared }

    var body: some View {
        HStack(spacing: 6) {
            chip(speedLabel) { showSpeed = true }
            chip(sleepLabel, highlighted: audio.sleepTimer.isActive) { showSleep = true }
            chip(icon: "bookmark", action: addBookmark)
        }
    }

    private var speedLabel: String {
        let rate = audio.currentBook?.id == book.id ? audio.player.playbackRate : book.speed
        return "\(rate.formatted(.number.precision(.fractionLength(0...1))))×"
    }

    private var sleepLabel: String {
        guard let remaining = audio.sleepTimeRemaining else { return String(localized: "Timer") }
        return "\(Int((remaining / 60).rounded(.up))) min"
    }

    private func chip(_ title: String, highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .background(highlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: Capsule())
    }

    private func chip(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .background(.quaternary, in: Capsule())
    }

    private func addBookmark() {
        WKInterfaceDevice.current().play(.click)
        audio.addBookmark()
    }
}
