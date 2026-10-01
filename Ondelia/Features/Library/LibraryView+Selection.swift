import SwiftUI

// MARK: - Multi-selection and bulk actions
extension LibraryView {
    var selectedBooks: [AudiobookModel] {
        audiobookManager.audiobooks.filter { selectedIDs.contains($0.id) }
    }

    func endSelecting() {
        selecting = false
        selectedIDs.removeAll()
    }

    /// Selecting: the tap toggles the book. Otherwise it opens the detail screen.
    func tapBook(_ audiobook: AudiobookModel) {
        guard selecting else {
            audiobookForDetail = audiobook
            return
        }
        if selectedIDs.remove(audiobook.id) == nil {
            selectedIDs.insert(audiobook.id)
        }
    }

    /// The check badge over a grid cell while selecting. The list row draws `SelectionMark`
    /// itself, in place of its chevron.
    @ViewBuilder
    func selectionBadge(for audiobook: AudiobookModel) -> some View {
        if selecting {
            SelectionMark(isSelected: selectedIDs.contains(audiobook.id))
                .padding(8)
        }
    }

    // ponytail: each mark/delete call refetches the library. Fine for tens of books; batch the
    // save in ListenerState if someone selects hundreds.
    func markSelected(finished: Bool) {
        for book in selectedBooks {
            ListenerState.shared.apply(finished ? .finish : .unfinish, to: book, from: .listener)
        }
        endSelecting()
    }

    func deleteSelected(_ books: [AudiobookModel]) {
        for book in books {
            audiobookManager.deleteAudiobook(book)
        }
        if let shown = audiobookForDetail, books.contains(where: { $0.id == shown.id }) {
            audiobookForDetail = nil
        }
        endSelecting()
    }

    @ToolbarContentBuilder
    var libraryToolbar: some ToolbarContent {
        if selecting {
            ToolbarItem(placement: .topBarLeading) {
                Button(NSLocalizedString("Cancel", comment: "Cancel button")) {
                    withHapticFeedback { endSelecting() }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    bulkMenuItems
                } label: {
                    Text(String(
                        format: NSLocalizedString("%d selected", comment: "Selection count in the library toolbar"),
                        selectedIDs.count
                    ))
                    .font(.system(size: 15, weight: .semibold))
                }
            }
        } else {
            // Selecting acts on library books; the server shelf has none to act on.
            if !showsServer {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("Select", comment: "Enter library selection mode")) {
                        withHapticFeedback { selecting = true }
                    }
                    .disabled(shelfBooks.isEmpty)
                }
            }
            importToolbarItem
        }
    }

    @ViewBuilder
    var bulkMenuItems: some View {
        Button {
            selectedIDs = Set(shelfBooks.map(\.id))
        } label: {
            Label(NSLocalizedString("Select All", comment: "Select every book on the shelf"), systemImage: "checklist")
        }
        .disabled(selectedIDs.count == shelfBooks.count)

        Button {
            let books = selectedBooks
            endSelecting()
            openCollectionPicker(for: books)
        } label: {
            Label(NSLocalizedString("Add to Collection", comment: "Collection picker title"), systemImage: "folder.badge.plus")
        }
        .disabled(selectedIDs.isEmpty)

        Button {
            withHapticFeedback { markSelected(finished: true) }
        } label: {
            Label(NSLocalizedString("Mark as Read", comment: "Mark as read"), systemImage: "checkmark.circle")
        }
        .disabled(selectedIDs.isEmpty)

        Button {
            withHapticFeedback { markSelected(finished: false) }
        } label: {
            Label(NSLocalizedString("Mark as Unread", comment: "Mark as unread"), systemImage: "circle")
        }
        .disabled(selectedIDs.isEmpty)

        Divider()

        Button(role: .destructive) {
            activeAlert = .confirmDeleteMany(selectedBooks)
        } label: {
            Label(NSLocalizedString("Delete", comment: "Delete button"), systemImage: "trash")
        }
        .tint(.red)
        .disabled(selectedIDs.isEmpty)
    }
}

/// The circle that becomes a check when a book is picked.
struct SelectionMark: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, isSelected ? Color.accentColor : Color.black.opacity(0.35))
            .accessibilityHidden(true)
    }
}
