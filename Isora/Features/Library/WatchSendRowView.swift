import SwiftUI

/// "Send to Apple Watch" and what the watch currently holds of this book. Draws nothing at all
/// unless a watch is paired with the app installed, which is most people.
struct WatchSendRowView: View {
    let audiobook: AudiobookModel

    private let sync = WatchSyncService.shared

    var body: some View {
        if sync.isPaired && sync.isWatchAppInstalled {
            VStack(spacing: 6) {
                Button { sync.sendToWatch(book: audiobook) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "applewatch").font(.system(size: 13, weight: .semibold))
                        Text("Send to Apple Watch")
                    }
                    .font(.system(size: 13.5, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .glassEffect(.regular, in: Capsule())
                }
                .buttonStyle(.plain)

                if let status {
                    Text(status)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// What is happening right now beats what is already there, since only one of them moves.
    private var status: String? {
        if let item = sync.inFlight(for: audiobook.id) {
            switch item.state {
            case .queued:
                return String(localized: "Chapter \(item.chapterNumber) queued")
            case .exporting:
                return String(localized: "Preparing chapter \(item.chapterNumber)")
            case .sending(let fraction):
                let percent = Int((fraction * 100).rounded())
                return String(localized: "Sending chapter \(item.chapterNumber) · \(percent) %")
            case .sent, .failed:
                break
            }
        }
        let count = sync.chaptersOnWatch[audiobook.id]?.count ?? 0
        guard count > 0 else { return nil }
        return String(localized: "\(count) chapters on the watch")
    }
}
