import SwiftUI

/// Closures the library hosts for a book's actions: the alerts and sheets live on LibraryView.
struct BookActions {
    var rename: (AudiobookModel) -> Void
    var changeCover: (AudiobookModel) -> Void
    var linkHardcover: (AudiobookModel) -> Void
    var addToCollection: (AudiobookModel) -> Void
    var delete: (AudiobookModel) -> Void
}

/// The menu items for one book, shared by the library context menus and the detail screen.
struct BookActionsMenu: View {
    let audiobook: AudiobookModel
    let actions: BookActions

    var body: some View {
        Button {
            PlayQueue.shared.toggle(audiobook)
        } label: {
            if PlayQueue.shared.contains(audiobook) {
                Label(NSLocalizedString("Remove from Queue", comment: "Remove from queue button"), systemImage: "text.badge.minus")
            } else {
                Label(NSLocalizedString("Add to Queue", comment: "Add to queue button"), systemImage: "text.badge.plus")
            }
        }

        Button {
            actions.rename(audiobook)
        } label: {
            Label(NSLocalizedString("Rename", comment: "Rename button"), systemImage: "pencil")
        }

        Button {
            if audiobook.isFinished {
                AudiobookManager.shared.markAsUnread(audiobook)
            } else {
                AudiobookManager.shared.markAsRead(audiobook)
            }
        } label: {
            if audiobook.isFinished {
                Label(NSLocalizedString("Mark as Unread", comment: "Mark as unread"), systemImage: "circle")
            } else {
                Label(NSLocalizedString("Mark as Read", comment: "Mark as read"), systemImage: "checkmark.circle")
            }
        }

        Button {
            actions.addToCollection(audiobook)
        } label: {
            Label(NSLocalizedString("Add to Collection", comment: "Collection picker title"), systemImage: "folder.badge.plus")
        }

        Button {
            actions.changeCover(audiobook)
        } label: {
            Label(NSLocalizedString("Change Cover Image", comment: "Change cover image button"), systemImage: "photo")
        }

        if HardcoverService.shared.isLinked && audiobook.hardcover == nil {
            Button {
                actions.linkHardcover(audiobook)
            } label: {
                Label(NSLocalizedString("Link to Hardcover", comment: "Hardcover link menu item"), systemImage: "link")
            }
        }

        Divider()

        Button(role: .destructive) {
            actions.delete(audiobook)
        } label: {
            Label(NSLocalizedString("Delete", comment: "Delete button"), systemImage: "trash")
        }
        // The destructive role reddens the title; the glyph still follows the app accent.
        .tint(.red)
    }
}
