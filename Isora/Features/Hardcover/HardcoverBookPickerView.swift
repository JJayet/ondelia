import SwiftUI

/// Picks the Hardcover book an audiobook stands for.
///
/// Opens on the results for the audiobook's own title and author; the search field is there for
/// the rips whose tags are wrong enough that the automatic query misses.
struct HardcoverBookPickerView: View {
    let audiobook: AudiobookModel

    @Environment(\.dismiss) private var dismiss
    private let service = HardcoverService.shared

    @State private var hits: [HardcoverAPI.SearchHit] = []
    @State private var errorMessage: String?
    @State private var isSearching = false
    @State private var query = ""
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(NSLocalizedString("Hardcover", comment: "Hardcover picker title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(NSLocalizedString("Cancel", comment: "Cancel button")) { dismiss() }
                    }
                    if audiobook.hardcover != nil {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(NSLocalizedString("Unlink", comment: "Hardcover unlink button"), role: .destructive) {
                                Task {
                                    await service.link(nil, to: audiobook)
                                    dismiss()
                                }
                            }
                        }
                    }
                }
                .searchable(
                    text: $query,
                    prompt: Text(NSLocalizedString("Title and author", comment: "Hardcover search prompt"))
                )
                .onChange(of: query) { _, newValue in scheduleSearch(newValue) }
                .task { await runSearch(service.searchQuery(for: audiobook)) }
                .onDisappear { searchTask?.cancel() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isSearching {
            ProgressView(NSLocalizedString("Searching…", comment: "Hardcover search in progress"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            ContentUnavailableView(
                NSLocalizedString("Search Failed", comment: "Hardcover search failure title"),
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
        } else if hits.isEmpty {
            ContentUnavailableView(
                NSLocalizedString("No Matches", comment: "Hardcover empty results title"),
                systemImage: "magnifyingglass",
                description: Text(NSLocalizedString(
                    "Try searching for the title and author.",
                    comment: "Hardcover empty results message"
                ))
            )
        } else {
            List(hits) { hit in
                Button {
                    Task {
                        await service.link(HardcoverLink(hit), to: audiobook)
                        dismiss()
                    }
                } label: {
                    HardcoverBookRow(
                        title: hit.title,
                        author: hit.author,
                        artworkURL: hit.artworkURL,
                        isLinked: audiobook.hardcover?.id == hit.id
                    )
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }

    /// Waits out the typing before searching: one request per pause, not one per keystroke.
    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let effective = trimmed.isEmpty ? service.searchQuery(for: audiobook) : trimmed
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await runSearch(effective)
        }
    }

    private func runSearch(_ text: String) async {
        isSearching = true
        errorMessage = nil
        do {
            hits = try await service.search(text)
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        isSearching = false
    }
}

/// One search result, or the book an audiobook is already linked to.
struct HardcoverBookRow: View {
    let title: String
    let author: String
    let artworkURL: URL?
    var isLinked = false

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: artworkURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.2))
            }
            .frame(width: 44, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(2)
                Text(author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isLinked {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .accessibilityLabel(NSLocalizedString("Linked", comment: "Hardcover linked book"))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview("Hardcover Row") {
    List {
        HardcoverBookRow(
            title: "Awaken Online: Catharsis",
            author: "Travis Bagwell",
            artworkURL: nil,
            isLinked: true
        )
    }
}
