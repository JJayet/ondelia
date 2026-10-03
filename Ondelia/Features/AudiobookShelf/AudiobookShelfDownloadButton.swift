import SwiftUI

/// "Download" under a streamed book's play button, then its progress while it downloads.
struct AudiobookShelfDownloadButton: View {
    let book: AudiobookModel
    private let service = AudiobookShelfService.shared

    var body: some View {
        let item = service.itemID(for: book)
        Group {
            if let item, let progress = service.downloads[item] {
                HStack(spacing: 10) {
                    if let fraction = progress.fraction {
                        ProgressLine(value: fraction, height: 4)
                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    } else {
                        ProgressView()
                        Text(progress.received.formatted(.byteCount(style: .file)))
                            .monospacedDigit()
                    }
                }
                .font(.system(size: 13.5, weight: .semibold))
                .padding(.horizontal, 18)
            } else if let item, service.importing.contains(item) {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(NSLocalizedString("Importing...", comment: "Importing audiobook status"))
                }
                .font(.system(size: 13.5, weight: .semibold))
            } else {
                Button {
                    withHapticFeedback { service.download(book) }
                } label: {
                    Label(
                        NSLocalizedString("Download", comment: "AudiobookShelf: download item button"),
                        systemImage: "arrow.down.circle"
                    )
                    .font(.system(size: 15.5, weight: .semibold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .glassEffect(.regular, in: Capsule())
    }
}
