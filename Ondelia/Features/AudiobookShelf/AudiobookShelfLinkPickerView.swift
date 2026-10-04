import SwiftUI

/// Picks the server audiobook a Library audiobook is a recording of, and gives it that server
/// link. The two then show as one, its position syncs with the server, and another device
/// without the file can stream it. Never guessed: the listener picks, starting from the title.
struct AudiobookShelfLinkPickerView: View {
    let audiobook: AudiobookModel

    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    private let catalog = AudiobookShelfCatalog.shared

    init(audiobook: AudiobookModel) {
        self.audiobook = audiobook
        _query = State(initialValue: audiobook.title ?? "")
    }

    private var matches: [AudiobookShelfAPI.Item] {
        let items = catalog.unjoined(linked: AudiobookShelfService.shared.libraryBooks)
        let q = normalize(query.trimmingCharacters(in: .whitespaces))
        guard !q.isEmpty else { return items }
        return items.filter { normalize($0.title).contains(q) || normalize($0.author ?? "").contains(q) }
    }

    var body: some View {
        NavigationStack {
            List(matches) { item in
                Button {
                    withHapticFeedback {
                        AudiobookShelfService.shared.link(audiobook, to: item)
                        dismiss()
                    }
                } label: {
                    SearchResultRow(entry: .server(item), query: query)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .overlay {
                if matches.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle(NSLocalizedString("Link to Server Audiobook", comment: "Server link picker title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "Cancel button")) { dismiss() }
                }
            }
        }
    }

    private func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

extension AudiobookShelfService {
    /// Gives a Library audiobook its server link, by the listener's choice.
    func link(_ book: AudiobookModel, to item: AudiobookShelfAPI.Item) {
        guard libraryBooks[item.id] == nil, itemID(for: book) == nil else { return }
        Self.insertLink(audiobookID: book.id, itemID: item.id, serverID: primary?.id, context: SwiftDataController.shared.context)
        SwiftDataController.shared.save()
        linksDidChange()
        AudiobookManager.shared.fetchAudiobooks()
    }
}
