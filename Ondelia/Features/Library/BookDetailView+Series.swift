import SwiftUI

// MARK: - Series picker
extension BookDetailView {
    /// One request, then the dialog — only when there is something to choose from.
    func openSeriesPicker() async {
        seriesOptions = await HardcoverService.shared.seriesOptions(for: audiobook)
        guard !seriesOptions.isEmpty else { return }
        withHapticFeedback { showingSeriesPicker = true }
    }

    @ViewBuilder
    var seriesPickerButtons: some View {
        ForEach(seriesOptions) { series in
            Button {
                Task { await HardcoverService.shared.setSeries(series, for: audiobook) }
            } label: {
                let badge = HardcoverLink(id: 0, title: "", author: "", seriesPosition: series.position).volumeBadge
                let title = [series.name, badge].compactMap { $0 }.joined(separator: " ")
                Text(series.id == audiobook.hardcover?.seriesID ? "✓ \(title)" : title)
            }
        }
    }
}
