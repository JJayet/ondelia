import SwiftUI
import TipKit

/// What the paired watch is holding, and the one button that empties it. Absent entirely when
/// no watch is paired.
struct WatchSettingsSection: View {
    private let sync = WatchSyncService.shared

    var body: some View {
        if sync.isPaired && sync.isWatchAppInstalled {
            TipView(WatchTip())
            SettingsSection(title: String(localized: "Apple Watch")) {
                if held.isEmpty {
                    SettingsRow(title: String(localized: "Nothing on the watch"))
                } else {
                    ForEach(held, id: \.id) { book in
                        SettingsRow(title: book.title ?? AudiobookModel.unknownTitle) {
                            SettingsValue(text: String(localized: "\(book.count) chapters"), chevron: false)
                        }
                        SettingsDivider()
                    }

                    Button { withHapticFeedback { sync.clearWatch() } } label: {
                        SettingsRow(title: String(localized: "Clear Watch"), titleColor: .red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private struct HeldBook {
        let id: UUID
        let title: String?
        let count: Int
    }

    private var held: [HeldBook] {
        sync.chaptersOnWatch
            .filter { !$0.value.isEmpty }
            .map { HeldBook(id: $0.key, title: sync.book($0.key)?.title, count: $0.value.count) }
            .sorted { ($0.title ?? "") < ($1.title ?? "") }
    }
}
