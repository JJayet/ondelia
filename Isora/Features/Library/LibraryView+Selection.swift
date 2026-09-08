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

    /// The check badge over a cell while selecting. Sits on the cover in the grid and on the
    /// card's corner in the list; the same view serves both.
    @ViewBuilder
    func selectionBadge(for audiobook: AudiobookModel) -> some View {
        if selecting {
            let isSelected = selectedIDs.contains(audiobook.id)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, isSelected ? Color.accentColor : Color.black.opacity(0.35))
                .padding(8)
                .accessibilityHidden(true)
        }
    }

    // ponytail: each mark/delete call refetches the library. Fine for tens of books; batch the
    // save in AudiobookManager if someone selects hundreds.
    func markSelected(finished: Bool) {
        for book in selectedBooks {
            finished ? audiobookManager.markAsRead(book) : audiobookManager.markAsUnread(book)
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
            ToolbarItem(placement: .topBarLeading) {
                Button(NSLocalizedString("Select", comment: "Enter library selection mode")) {
                    withHapticFeedback { selecting = true }
                }
                .disabled(shelfBooks.isEmpty)
            }
            importToolbarItem
        }
    }

    @ViewBuilder
    private var bulkMenuItems: some View {
        Button {
            selectedIDs = Set(shelfBooks.map(\.id))
        } label: {
            Label(NSLocalizedString("Select All", comment: "Select every book on the shelf"), systemImage: "checklist")
        }
        .disabled(selectedIDs.count == shelfBooks.count)

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
        .disabled(selectedIDs.isEmpty)
    }
}
