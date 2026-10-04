import SwiftUI

/// Closures the library hosts for a book's actions: the alerts and sheets live on LibraryView.
struct BookActions {
    var rename: (AudiobookModel) -> Void
    var linkHardcover: (AudiobookModel) -> Void
    var addToCollection: (AudiobookModel) -> Void
    var linkServer: (AudiobookModel) -> Void
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
            ListenerState.shared.apply(audiobook.isFinished ? .unfinish : .finish, to: audiobook, from: .listener)
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

        // A streamed book: download it, or cancel its download.
        let server = AudiobookShelfService.shared
        if let item = server.itemID(for: audiobook) {
            if server.downloads[item] != nil {
                Button(role: .destructive) {
                    server.cancelDownload(id: item)
                } label: {
                    Label(NSLocalizedString("Cancel Download", comment: "AudiobookShelf: cancel download button"), systemImage: "xmark")
                }
            } else if server.canStream(audiobook), !server.importing.contains(item) {
                Button {
                    server.download(audiobook)
                } label: {
                    Label(NSLocalizedString("Download", comment: "AudiobookShelf: download item button"), systemImage: "arrow.down.circle")
                }
            }
        }

        if HardcoverService.shared.isLinked && audiobook.hardcover == nil {
            Button {
                actions.linkHardcover(audiobook)
            } label: {
                Label(NSLocalizedString("Link to Hardcover", comment: "Hardcover link menu item"), systemImage: "link")
            }
        }

        // An imported audiobook that is also on the server: link the two so it shows once.
        if AudiobookShelfCatalog.shared.isActive, AudiobookShelfService.shared.itemID(for: audiobook) == nil {
            Button {
                actions.linkServer(audiobook)
            } label: {
                Label(NSLocalizedString("Link to Server Audiobook…", comment: "Server link menu item"), systemImage: "link.icloud")
            }
        }

        Divider()

        // A server audiobook with no audio here is hidden rather than deleted: deleting would
        // only bring it back as a server audiobook. One with audio here can drop the audio.
        let item = server.itemID(for: audiobook)
        let hasFile = AudiobookManager.shared.hasFile(audiobook)
        if item != nil, hasFile {
            Button(role: .destructive) {
                server.removeDownload(audiobook)
            } label: {
                Label(NSLocalizedString("Remove Download", comment: "AudiobookShelf: delete a downloaded book's audio, keep it streamable"), systemImage: "icloud.and.arrow.down")
            }
            .tint(.red)
        }
        if let item, !hasFile, let serverID = server.serverID(for: audiobook) {
            Button(role: .destructive) {
                AudiobookShelfHidden.shared.hide(.book, item, name: audiobook.title ?? "", on: serverID)
            } label: {
                Label(NSLocalizedString("Hide", comment: "Hide a server audiobook, series or author"), systemImage: "eye.slash")
            }
            .tint(.red)
        } else {
            Button(role: .destructive) {
                actions.delete(audiobook)
            } label: {
                Label(NSLocalizedString("Delete", comment: "Delete button"), systemImage: "trash")
            }
            // The destructive role reddens the title; the glyph still follows the app accent.
            .tint(.red)
        }
    }
}
