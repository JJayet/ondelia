import CarPlay
import ImageIO
import UIKit

/// The CarPlay library: three tabs, plus the book list a collection row pushes.
///
/// Rows come straight from `AudiobookManager`; nothing is cached but the cover thumbnails.
/// `reload(_:)` is called by the scene delegate each time a template is about to appear.
@MainActor
final class CarPlayLibrary {
    private weak var interfaceController: CPInterfaceController?

    let tabBar: CPTabBarTemplate
    private let continueTemplate: CPListTemplate
    private let libraryTemplate: CPListTemplate
    private let collectionsTemplate: CPListTemplate
    /// The collection list on screen, so coming back from Now Playing refreshes its rows too.
    private var pushedCollection: (template: CPListTemplate, id: UUID)?

    /// Covers scaled to the row size. A full 1024 px cover is ~4 MiB decoded and CarPlay keeps
    /// every row's image alive, so a library of a hundred books would be jetsam bait.
    /// ponytail: never invalidated; a cover changed while the car is connected shows the old
    /// one until the next connection.
    private var thumbnails: [UUID: UIImage] = [:]

    init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController

        continueTemplate = CPListTemplate(
            title: NSLocalizedString("Continue Listening", comment: "CarPlay tab: books in progress"),
            sections: []
        )
        continueTemplate.tabImage = UIImage(systemName: "play.circle")
        continueTemplate.emptyViewTitleVariants = [
            NSLocalizedString("Nothing in progress", comment: "CarPlay empty state: no book started")
        ]

        libraryTemplate = CPListTemplate(
            title: NSLocalizedString("Library", comment: "Library tab title"),
            sections: []
        )
        libraryTemplate.tabImage = UIImage(systemName: "books.vertical")
        libraryTemplate.emptyViewTitleVariants = [
            NSLocalizedString("Your library is empty", comment: "CarPlay empty state: no books")
        ]

        collectionsTemplate = CPListTemplate(
            title: NSLocalizedString("Collections", comment: "Existing collections section"),
            sections: []
        )
        collectionsTemplate.tabImage = UIImage(systemName: "square.stack")
        collectionsTemplate.emptyViewTitleVariants = [
            NSLocalizedString("No collections", comment: "CarPlay empty state: no collections")
        ]

        tabBar = CPTabBarTemplate(templates: [continueTemplate, libraryTemplate, collectionsTemplate])
    }

    // MARK: - Ordering (pure, tested)

    /// Started, unfinished, most recently played first.
    static func continueBooks(_ books: [AudiobookModel]) -> [AudiobookModel] {
        books
            .filter { $0.currentPosition > 0 && !$0.isFinished }
            .sorted { $0.lastPlayed > $1.lastPlayed }
    }

    /// Every book, by title.
    static func libraryBooks(_ books: [AudiobookModel]) -> [AudiobookModel] {
        books.sorted {
            ($0.title ?? "").localizedStandardCompare($1.title ?? "") == .orderedAscending
        }
    }

    // MARK: - Reload

    /// Rebuilds one list, or every list when no template is named.
    func reload(_ template: CPTemplate? = nil) {
        let library = AudiobookManager.shared
        if template == nil || template === continueTemplate {
            continueTemplate.updateSections([section(of: Self.continueBooks(library.audiobooks))])
        }
        if template == nil || template === libraryTemplate {
            libraryTemplate.updateSections([section(of: Self.libraryBooks(library.audiobooks))])
        }
        if template == nil || template === collectionsTemplate {
            collectionsTemplate.updateSections([collectionsSection(library.collections)])
        }
        if let pushed = pushedCollection, template == nil || template === pushed.template,
           let collection = library.collections.first(where: { $0.id == pushed.id }) {
            pushed.template.updateSections([section(of: library.orderedBooks(in: collection))])
        }
    }

    // MARK: - Rows

    private func section(of books: [AudiobookModel]) -> CPListSection {
        CPListSection(items: books.prefix(CPListTemplate.maximumItemCount).map(item(for:)))
    }

    private func item(for book: AudiobookModel) -> CPListItem {
        let audio = GlobalAudioManager.shared
        let item = CPListItem(
            text: book.title ?? AudiobookModel.unknownTitle,
            detailText: book.author ?? AudiobookModel.unknownAuthor,
            image: thumbnail(for: book)
        )
        item.playbackProgress = CGFloat(book.progressFraction)
        item.isPlaying = audio.currentAudiobook?.id == book.id && audio.isPlaying()
        item.handler = { [weak self] _, completion in
            PlaybackCommands.play(book)
            self?.showNowPlaying(completion)
        }
        return item
    }

    private func collectionsSection(_ collections: [CollectionModel]) -> CPListSection {
        let items = collections.prefix(CPListTemplate.maximumItemCount).map { collection in
            let count = collection.bookIDs.count
            let item = CPListItem(
                text: collection.name,
                detailText: String(
                    format: NSLocalizedString("%d books", comment: "CarPlay collection row: number of books"),
                    count
                ),
                image: UIImage(systemName: collection.isSeries ? "books.vertical" : "square.stack")
            )
            item.handler = { [weak self] _, completion in
                self?.push(collection, completion: completion)
            }
            return item
        }
        return CPListSection(items: items)
    }

    // MARK: - Navigation

    private func push(_ collection: CollectionModel, completion: @escaping () -> Void) {
        let template = CPListTemplate(title: collection.name, sections: [])
        pushedCollection = (template, collection.id)
        reload(template)
        interfaceController?.pushTemplate(template, animated: true) { _, _ in completion() }
    }

    private func showNowPlaying(_ completion: @escaping () -> Void) {
        interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true) { _, _ in completion() }
    }

    // MARK: - Thumbnails

    private func thumbnail(for book: AudiobookModel) -> UIImage? {
        if let cached = thumbnails[book.id] { return cached }
        guard let data = book.coverImageData else { return nil }
        let scale = interfaceController?.carTraitCollection.displayScale ?? 2
        let pixels = CPListItem.maximumImageSize.height * scale
        guard let image = Self.thumbnail(data, maxPixels: pixels, scale: scale) else { return nil }
        thumbnails[book.id] = image
        return image
    }

    /// Decodes straight to the target size; `UIImage(data:)` would decode the full cover first.
    private nonisolated static func thumbnail(_ data: Data, maxPixels: CGFloat, scale: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixels)
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
}
