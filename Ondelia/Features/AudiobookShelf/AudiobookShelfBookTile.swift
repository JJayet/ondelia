import SwiftUI

extension EnvironmentValues {
    /// Plays a library book from the server shelf. Set by `LibraryView`, which owns the player.
    @Entry var audiobookShelfPlay: (@MainActor (AudiobookModel) -> Void)?
    /// Library books by server item, computed once per shelf rather than once per tile.
    @Entry var audiobookShelfLibraryBooks: [String: AudiobookModel] = [:]
    /// The server library the shelf shows, for actions that fetch more of it.
    @Entry var audiobookShelfLibrary = ""
    /// Opens the collection picker for a book. Set by `LibraryView`, which owns the sheet.
    @Entry var audiobookShelfAddToCollection: (@MainActor (AudiobookModel) -> Void)?
}

extension View {
    /// Long press on a series or an author: download every book of it not on this device.
    func audiobookShelfDownloadAllMenu(_ group: AudiobookShelfService.DownloadGroup) -> some View {
        modifier(AudiobookShelfDownloadAllMenu(group: group))
    }
}

private struct AudiobookShelfDownloadAllMenu: ViewModifier {
    let group: AudiobookShelfService.DownloadGroup
    @Environment(\.audiobookShelfLibrary) private var library

    func body(content: Content) -> some View {
        content.contextMenu {
            Button {
                withHapticFeedback(.medium) {}
                Task { await AudiobookShelfService.shared.downloadAll(group, library: library) }
            } label: {
                Label(
                    NSLocalizedString("Download All", comment: "AudiobookShelf: download every book of a series or author"),
                    systemImage: "arrow.down.circle"
                )
            }
        }
    }
}

/// One server book on the shelf, drawn like `AudiobookGridItemView`: the cover, the cloud badge
/// the library puts on books that are not on this device, and the title.
///
/// Tapping plays the book, from the device when it is there and streamed from the server
/// otherwise; a long press downloads it. A downloaded book keeps the entry it was streamed
/// under, with its position.
struct AudiobookShelfBookTile: View {
    let item: AudiobookShelfAPI.Item
    var columns = 2
    /// "Book 3" in a series, instead of the author.
    var showsSequence = false

    @Environment(\.audiobookShelfPlay) private var play
    @Environment(\.audiobookShelfLibraryBooks) private var libraryBooks
    private let service = AudiobookShelfService.shared

    private var localBook: AudiobookModel? { libraryBooks[item.id] }
    private var isOnDevice: Bool { localBook.map(AudiobookManager.shared.hasFile) ?? false }

    var body: some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 8) {
                AudiobookShelfCover(item: item.id, title: item.title)
                    .overlay(alignment: .topLeading) {
                        if !isOnDevice, service.downloads[item.id] == nil, !service.importing.contains(item.id) {
                            AudiobookShelfCloudBadge()
                        }
                    }
                    .overlay { transferOverlay }

                Text(item.title)
                    .font(.system(size: columns >= 3 ? 11.5 : 12.5, weight: .semibold))
                    .lineLimit(columns >= 4 ? 1 : 2)
                    .multilineTextAlignment(.leading)

                if columns < 4, let meta {
                    Text(meta)
                        .font(.system(size: columns >= 3 ? 10 : 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { AudiobookShelfItemMenu(item: item, isOnDevice: isOnDevice, joined: localBook != nil) }
        .accessibilityValue(accessibilityState)
    }

    private var meta: String? {
        if showsSequence, let sequence = item.sequence {
            return String(format: NSLocalizedString("Book %@", comment: "AudiobookShelf: position in a series"), sequence)
        }
        let duration = item.media.duration.flatMap { $0 > 0 ? $0.hoursMinutesFormatted : nil }
        return [item.author, duration].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
    }

    @ViewBuilder private var transferOverlay: some View {
        if let progress = service.downloads[item.id] {
            AudiobookShelfTransferOverlay(fraction: progress.fraction)
        } else if service.importing.contains(item.id) {
            AudiobookShelfTransferOverlay(fraction: nil)
        }
    }

    private var accessibilityState: String {
        if service.downloads[item.id] != nil {
            return NSLocalizedString("Downloading...", comment: "AudiobookShelf download status in the library")
        }
        return isOnDevice ? "" : NSLocalizedString("Not on this device", comment: "Missing audio badge")
    }

    private func tap() {
        withHapticFeedback { service.play(item, local: localBook, with: play) }
    }
}

/// The library's "not on this device" badge.
struct AudiobookShelfCloudBadge: View {
    var body: some View {
        Image(systemName: "icloud.and.arrow.down")
            .font(.system(size: 12, weight: .semibold))
            .padding(6)
            .background(.black.opacity(0.45), in: Circle())
            .foregroundStyle(.white)
            .padding(6)
            .accessibilityHidden(true)
    }
}

/// Darkens a cover while its book downloads (a ring when the size is known) or imports.
struct AudiobookShelfTransferOverlay: View {
    let fraction: Double?

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.black.opacity(0.45))
            .overlay {
                if let fraction {
                    ZStack {
                        Circle().stroke(.white.opacity(0.3), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: fraction)
                            .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear, value: fraction)
                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                    .frame(width: 44, height: 44)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .allowsHitTesting(false)
    }
}

/// A square server cover, drawn like `CoverArtView`.
struct AudiobookShelfCover: View {
    let item: String
    var title = ""
    var size: CGFloat?
    var cornerRadius: CGFloat = 16

    @State private var image: UIImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .frame(width: size, height: size)
            .overlay {
                if let image = image ?? AudiobookShelfImages.cached(item) {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    placeholder
                }
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            .task(id: item) { await load() }
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.55), Color.accentColor.opacity(0.2)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        // Bottom, not top: the top-leading corner carries the cloud badge.
        .overlay(alignment: .bottomLeading) {
            if (size ?? 100) >= 60 {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .padding(10)
            }
        }
    }

    private func load() async {
        image = await AudiobookShelfImages.load(key: item) { server, token in
            AudiobookShelfAPI.coverRequest(server: server, token: token, item: item)
        }
    }
}

/// Server images fetched with the bearer header (`AsyncImage` cannot set one). Kept in memory
/// for scrolling back, and on disk so a relaunch does not fetch every cover of a big library
/// again.
@MainActor
enum AudiobookShelfImages {
    private static let cache = NSCache<NSString, UIImage>()

    /// Caches: the server holds the originals, so the system may purge these.
    nonisolated static var folder: URL {
        URL.cachesDirectory.appending(path: "AudiobookShelfImages", directoryHint: .isDirectory)
    }

    nonisolated private static func file(_ key: String) -> URL {
        folder.appending(path: AudiobookShelfAPI.safeFilename(key))
    }

    static func cached(_ key: String) -> UIImage? { cache.object(forKey: key as NSString) }

    static func load(key: String, request: (URL, String) -> URLRequest) async -> UIImage? {
        if let hit = cached(key) { return hit }
        let file = file(key)
        // Off the main thread: a grid of covers decoding from disk at once stutters the scroll.
        if let stored = await Task.detached(priority: .userInitiated, operation: {
            (try? Data(contentsOf: file)).flatMap(UIImage.init(data:))?.preparingForDisplay()
        }).value {
            cache.setObject(stored, forKey: key as NSString)
            return stored
        }
        let service = AudiobookShelfService.shared
        guard let server = service.server, let token = service.token,
              let (data, response) = try? await URLSession.shared.data(for: request(server, token)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = await Task.detached(operation: { UIImage(data: data)?.preparingForDisplay() }).value
        else { return nil }
        cache.setObject(image, forKey: key as NSString)
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
        return image
    }

    /// Signed out: another account's covers have no business staying.
    static func forget() {
        cache.removeAllObjects()
        try? FileManager.default.removeItem(at: folder)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
