import SwiftUI

struct ImportingIndicatorView: View {
    @ObservedObject var manager: AudiobookManager
    init(manager: AudiobookManager) { self.manager = manager }
    init() { self.manager = AudiobookManager.shared }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.down.fill")
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("Importing...", comment: "Importing audiobook status"))
                    .font(.subheadline)
                    .foregroundColor(.primaryText)
                if let name = manager.currentImportFileName {
                    Text(name)
                        .font(.caption)
                        .foregroundColor(.secondaryText)
                        .lineLimit(1)
                }
                if manager.importQueueTotal > 1 {
                    Text("\(manager.importQueueCompleted + 1)/\(manager.importQueueTotal)")
                        .font(.caption2)
                        .foregroundColor(.secondaryText)
                }
            }
            Spacer()
        }
        .padding()
        .glassEffect(in:.rect(cornerRadius: 12))
    }
}
