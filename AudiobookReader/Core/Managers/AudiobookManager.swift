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

@Observable
class AudiobookManager: AudiobookManagerProtocol {
    static let shared = AudiobookManager()
    let swiftDataController: SwiftDataController
    
    var audiobooks: [AudiobookModel] = []
    var isImporting = false
    var importQueueTotal: Int = 0
    var importQueueCompleted: Int = 0
    var currentImportFileName: String? = nil
    var isLoadingLibrary = false
    var audiobookNeedingCover: AudiobookModel?
    var importErrorMessage: String?
    var mergePrompt: MergePrompt?
    
    var pendingImports: [(urls: [URL], completion: (() -> Void)?)] = []
    /// True from the moment an import starts until its merge offer has been answered.
    /// Imports run one at a time; see `handleImportRequest`.
    var isImportRunning = false
    var isDrainingImports = false
    /// Inbox files already handed to an import, so a second scan does not import them again.
    var inboxHandedOff: Set<String> = []
    /// Audiobooks split out of one folder: they all receive the cover picked for `audiobookNeedingCover`.
    var coverBatch: [AudiobookModel] = []
    /// Every audiobook the running import produced, so the merge offer knows what it would merge.
    var importBatch: [AudiobookModel] = []
    /// Name to suggest for that merge, set when the batch clearly came from one folder.
    var pendingMergeTitle: String?

    init(swiftDataController: SwiftDataController = .shared) {
        self.swiftDataController = swiftDataController
    }

    func getBookmarks(for audiobook: AudiobookModel) -> [BookmarkModel] {
        return audiobook.bookmarks
    }
    
    func markAsFinished(_ audiobook: AudiobookModel) {
        audiobook.isFinished = true
    }
    
    func resetProgress(for audiobook: AudiobookModel) {
        audiobook.currentPosition = 0
    }
    
    func updateProgress(for audiobook: AudiobookModel, currentTime: TimeInterval) {
        audiobook.currentPosition = currentTime
        audiobook.lastPlayed = Date()
        
        // Mark as finished if within 30 seconds of the end
        if audiobook.duration > 0 && (audiobook.duration - currentTime) <= 30 {
            audiobook.isFinished = true
        }
        
        swiftDataController.save()
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
    }
    
    @MainActor
    func deleteBookmark(_ bookmark: BookmarkModel) {
        let context = swiftDataController.context
        context.delete(bookmark)
        swiftDataController.save()
    }

    // MARK: - Cover Image Management
    @MainActor
    func updateCoverImage(for audiobook: AudiobookModel, with image: UIImage) {
        let imageData = image.jpegData(compressionQuality: 0.8)
        audiobook.coverImageData = imageData
        for sibling in coverBatch where sibling.persistentModelID != audiobook.persistentModelID {
            sibling.coverImageData = imageData
        }
        coverBatch.removeAll()
        swiftDataController.save()
        fetchAudiobooks()
        
        // Clear the needing cover flag if this was the audiobook that needed it
        if audiobookNeedingCover?.persistentModelID == audiobook.persistentModelID {
            audiobookNeedingCover = nil
        }
    }

    // MARK: - Progress Management (duplicate removed - the real implementation is earlier)
    
    // MARK: - Bookmark Management
    @MainActor
    func createBookmarkLegacy(for audiobook: AudiobookModel, at timestamp: TimeInterval, title: String, note: String? = nil) {
        // This is a duplicate - the real createBookmark using SwiftData is earlier in the file
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
    }
    
    // Legacy deleteBookmarkOld function removed - using SwiftData deleteBookmark instead
    
    // MARK: - Library Management
    @MainActor
    func deleteAudiobook(_ audiobook: AudiobookModel) {
        // Delete physical file
        if let fileURL = audiobook.resolvedFileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        // Delete from Core Data
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
    
    @MainActor
    func markAsRead(_ audiobook: AudiobookModel) {
        audiobook.isFinished = true
        audiobook.currentPosition = audiobook.duration // Set to end
        swiftDataController.save()
        fetchAudiobooks()
        
        Log.library.debug("✅ AudiobookManager: Marked audiobook as finished: \(audiobook.title ?? "Unknown")")
    }
    
    @MainActor
    func markAsUnread(_ audiobook: AudiobookModel) {
        audiobook.isFinished = false
        swiftDataController.save()
        fetchAudiobooks()
        
        Log.library.debug("🔄 AudiobookManager: Marked audiobook as unfinished: \(audiobook.title ?? "Unknown")")
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
