import SwiftUI

struct ImportingIndicatorView: View {
    let manager: AudiobookManager
    init(manager: AudiobookManager) { self.manager = manager }
    init() { self.manager = AudiobookManager.shared }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.down.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("Importing...", comment: "Importing audiobook status"))
                    .font(.subheadline)
                    .foregroundStyle(Color.primaryText)
                if let name = manager.currentImportFileName {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)
                }
                if manager.importQueueTotal > 1 {
                    Text(verbatim: "\(manager.importQueueCompleted + 1)/\(manager.importQueueTotal)")
                        .font(.caption2)
                        .foregroundStyle(Color.secondaryText)
                }
                // Determinate while the file copies, the one step long enough to measure;
                // indeterminate for the metadata and chapter reads around it.
                if let progress = manager.importProgress {
                    ProgressLine(value: progress, height: 3)
                        .padding(.top, 4)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .controlSize(.mini)
                        .padding(.top, 4)
                }
            }
            Spacer()
        }
        .padding()
        .glassEffect(in:.rect(cornerRadius: 12))
    }
}
