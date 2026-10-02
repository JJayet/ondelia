import SwiftUI

/// AudiobookShelf downloads in flight, one row each, above the shelf — the download half of
/// what `ImportingIndicatorView` shows once the file has arrived.
struct DownloadingIndicatorView: View {
    private let service = AudiobookShelfService.shared

    var body: some View {
        let downloads = service.downloads.sorted {
            $0.value.title.localizedStandardCompare($1.value.title) == .orderedAscending
        }
        VStack(spacing: 8) {
            ForEach(downloads, id: \.key) { id, progress in
                row(id: id, progress: progress)
            }
        }
    }

    private func row(id: String, progress: AudiobookShelfService.DownloadProgress) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("Downloading...", comment: "AudiobookShelf download status in the library"))
                    .font(.subheadline)
                    .foregroundStyle(Color.primaryText)
                if !progress.title.isEmpty {
                    Text(progress.title)
                        .font(.caption)
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)
                }
                Text(amount(progress))
                    .font(.caption2)
                    .foregroundStyle(Color.secondaryText)
                    .monospacedDigit()
                // A zipped folder is sent without a size, so only its bytes so far are known.
                if let fraction = progress.fraction {
                    ProgressLine(value: fraction, height: 3)
                        .padding(.top, 4)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .controlSize(.mini)
                        .padding(.top, 4)
                }
            }
            Spacer()
            Button {
                withHapticFeedback { service.cancelDownload(id: id) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(NSLocalizedString("Cancel Download", comment: "AudiobookShelf: cancel download button"))
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 12))
    }

    private func amount(_ progress: AudiobookShelfService.DownloadProgress) -> String {
        let received = progress.received.formatted(.byteCount(style: .file))
        guard let expected = progress.expected else { return received }
        return "\(received) / \(expected.formatted(.byteCount(style: .file)))"
    }
}
