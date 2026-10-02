import Foundation
import SwiftData
import UIKit

/// Offers to merge the audiobooks a single import produced into one book with chapters.
/// Raised *after* everything is imported, so ignoring it costs nothing: the books are already
/// in the library and `mergeAudiobooks` stays available from the library itself.
struct MergePrompt: Identifiable {
    let id = UUID()
    let suggestedTitle: String
    let bookCount: Int
    /// `true` merges the batch into one audiobook, `false` leaves the books separate.
    let respond: @MainActor (Bool) -> Void
}

@MainActor
@Observable
final class AudiobookManager {
    static let shared = AudiobookManager()
    let swiftDataController: SwiftDataController
    
    var audiobooks: [AudiobookModel] = []
    /// Every collection, series and hand-made. See `+Collections`.
    var collections: [CollectionModel] = []
    var collectionPrompt: CollectionPrompt?
    var isImporting = false
    var importQueueTotal: Int = 0
    var importQueueCompleted: Int = 0
    var currentImportFileName: String? = nil
    /// Bytes copied over bytes to copy for the file being imported; nil outside the copy, which
    /// is the only step long enough to measure.
    var importProgress: Double? = nil
    var isLoadingLibrary = false
    var importErrorMessage: String?
    var mergePrompt: MergePrompt?
    
    var pendingImports: [(urls: [URL], completion: (@Sendable () -> Void)?, onImported: ImportedHandler?)] = []
    /// Told which books the running import produced, once its merge offer has been answered.
    var onImported: ImportedHandler?
    /// True from the moment an import starts until its merge offer has been answered.
    /// Imports run one at a time; see `handleImportRequest`.
    var isImportRunning = false
    var isDrainingImports = false
    /// Inbox files already handed to an import, so a second scan does not import them again.
    var inboxHandedOff: Set<String> = []
    /// Audiobooks split out of one folder: they all receive the cover picked for any one of them.
    var coverBatch: [AudiobookModel] = []
    /// Every audiobook the running import produced, so the merge offer knows what it would merge.
    var importBatch: [AudiobookModel] = []
    /// Name to suggest for that merge, set when the batch clearly came from one folder.
    var pendingMergeTitle: String?
    /// See `+RemoteChanges`.
    var remoteChangeObserver: (any NSObjectProtocol)?
    var remoteRefetchTask: Task<Void, Never>?

    init(swiftDataController: SwiftDataController = .shared) {
        self.swiftDataController = swiftDataController
        observeRemoteChanges()
    }

    func getBookmarks(for audiobook: AudiobookModel) -> [BookmarkModel] {
        return audiobook.bookmarks
    }
    
    @MainActor
    func createBookmark(for audiobook: AudiobookModel, at timestamp: TimeInterval, title: String, note: String? = nil) {
        let context = swiftDataController.context
        let bookmark = BookmarkModel(
            title: title,
            note: note,
            timestamp: timestamp,
            dateCreated: Date()
        )
        
        bookmark.audiobook = audiobook
        context.insert(bookmark)

        swiftDataController.save()
        WatchSyncService.shared.pushSnapshot()
    }
    
    @MainActor
    func deleteBookmark(_ bookmark: BookmarkModel) {
        let context = swiftDataController.context
        context.delete(bookmark)
        swiftDataController.save()
        WatchSyncService.shared.pushSnapshot()
    }

    // MARK: - Cover Image Management
    @MainActor
    func updateCoverImage(for audiobook: AudiobookModel, with image: UIImage) {
        let imageData = image.coverJPEGData()
        audiobook.coverImageData = imageData
        CoverImageCache.invalidate(audiobook)
        for sibling in coverBatch where sibling.persistentModelID != audiobook.persistentModelID {
            sibling.coverImageData = imageData
            CoverImageCache.invalidate(sibling)
        }
        coverBatch.removeAll()
        swiftDataController.save()
        fetchAudiobooks()
    }

    // MARK: - Library Management
    @MainActor
    func deleteAudiobook(_ audiobook: AudiobookModel) {
        // Playback owns a reference to this model and writes progress into it on a timer, so it
        // has to let go before the model is deleted — otherwise the mini player keeps showing a
        // book that no longer exists and the lock screen keeps offering it.
        let audio = GlobalAudioManager.shared
        if audio.currentAudiobook?.id == audiobook.id {
            audio.unload()
        }

        PlayQueue.shared.remove(audiobook)
        removeFromAllCollections(bookID: audiobook.id)

        // Delete physical file
        if let fileURL = audiobook.resolvedFileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        // Delete from Core Data. Transcript windows, AudiobookShelf links and closed Hardcover
        // reads have no relationship to cascade through.
        let bookID = audiobook.id
        let windows = try? swiftDataController.context.fetch(
            FetchDescriptor<TranscriptWindowModel>(predicate: #Predicate { $0.audiobookID == bookID })
        )
        for window in windows ?? [] { swiftDataController.context.delete(window) }
        let links = try? swiftDataController.context.fetch(
            FetchDescriptor<AudiobookShelfLinkModel>(predicate: #Predicate { $0.audiobookID == bookID })
        )
        for link in links ?? [] { swiftDataController.context.delete(link) }
        let closedReads = try? swiftDataController.context.fetch(
            FetchDescriptor<HardcoverClosedReadModel>(predicate: #Predicate { $0.audiobookID == bookID })
        )
        for read in closedReads ?? [] { swiftDataController.context.delete(read) }
        swiftDataController.context.delete(audiobook)
        swiftDataController.save()
        fetchAudiobooks()
    }
    
    @MainActor
    func renameAudiobook(_ audiobook: AudiobookModel, newTitle: String) {
        guard !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        audiobook.title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        swiftDataController.save()
        fetchAudiobooks()
        
        Log.library.debug("✏️ AudiobookManager: Renamed audiobook to: \(newTitle)")
    }
    
    func searchAudiobooks(query: String) -> [AudiobookModel] {
        guard !query.isEmpty else { return audiobooks }
        
        return audiobooks.filter { audiobook in
            let title = audiobook.title?.lowercased() ?? ""
            let author = audiobook.author?.lowercased() ?? ""
            let searchQuery = query.lowercased()
            
            return title.contains(searchQuery) || author.contains(searchQuery)
        }
    }
}
