import SwiftUI

/// The long-press menu of a server book's tile and row: download it, or cancel the download.
/// A book not in the Library also offers what a Library book does; each makes it join first.
struct AudiobookShelfItemMenu: View {
    let item: AudiobookShelfAPI.Item
    let isOnDevice: Bool
    var joined = false
    @Environment(\.audiobookShelfAddToCollection) private var addToCollection
    @Environment(\.audiobookShelfPlay) private var play
    @Environment(\.audiobookShelfLibraryBooks) private var libraryBooks
    @AppStorage(AudiobookShelfService.Defaults.tapAction) private var tapAction = AudiobookShelfService.TapAction.stream
    private let service = AudiobookShelfService.shared

    var body: some View {
        if !joined {
            Button {
                service.join(item) { PlayQueue.shared.append($0) }
            } label: {
                Label(NSLocalizedString("Add to Queue", comment: "Add to queue button"), systemImage: "text.badge.plus")
            }
            Button {
                service.join(item) { ListenerState.shared.apply(.finish, to: $0, from: .listener) }
            } label: {
                Label(NSLocalizedString("Mark as Read", comment: "Mark as read"), systemImage: "checkmark.circle")
            }
            if let addToCollection {
                Button {
                    service.join(item, then: addToCollection.run)
                } label: {
                    Label(NSLocalizedString("Add to Collection", comment: "Collection picker title"), systemImage: "folder.badge.plus")
                }
            }
            Divider()
        }
        if service.downloads[item.id] != nil {
            Button(role: .destructive) {
                service.cancelDownload(id: item.id)
            } label: {
                Label(NSLocalizedString("Cancel Download", comment: "AudiobookShelf: cancel download button"), systemImage: "xmark")
            }
        } else if !isOnDevice, tapAction == .stream {
            Button {
                service.download(item)
            } label: {
                Label(NSLocalizedString("Download", comment: "AudiobookShelf: download item button"), systemImage: "arrow.down.circle")
            }
        }
        if !isOnDevice, tapAction == .download {
            Button {
                service.play(item, local: libraryBooks[item.id], with: play?.run)
            } label: {
                Label(NSLocalizedString("Stream", comment: "AudiobookShelf: stream item button"), systemImage: "play.circle")
            }
        }
    }
}

extension AudiobookShelfService {
    /// Plays a server book: its Library entry when it has one, streamed otherwise. A server
    /// book seen for the first time joins the Library on the way.
    func play(_ item: AudiobookShelfAPI.Item, local: AudiobookModel?, with play: (@MainActor (AudiobookModel) -> Void)?) {
        if let local {
            play?(local)
            return
        }
        join(item) { play?($0) }
    }

    /// A tap on a server book: plays it when on this device, else streams or downloads it as
    /// the listener chose.
    func open(_ item: AudiobookShelfAPI.Item, local: AudiobookModel?, with play: (@MainActor (AudiobookModel) -> Void)?) {
        let isOnDevice = local.map(AudiobookManager.shared.hasFile) ?? false
        if tapAction == .download, !isOnDevice {
            download(item)
        } else {
            self.play(item, local: local, with: play)
        }
    }

    /// Makes a server book join the Library, then acts on its new entry: anything that needs a
    /// record — a place in the queue, a Finish, a collection — needs it to join first.
    func join(_ item: AudiobookShelfAPI.Item, then action: @escaping @MainActor (AudiobookModel) -> Void) {
        Task {
            guard let book = await streamingBook(for: item) else { return }
            action(book)
        }
    }
}
