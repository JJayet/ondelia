import Foundation
import SwiftData
import UIKit

extension AudiobookManager {
    // MARK: - Fetch Operations
    @MainActor
    func fetchAudiobooks() {
        // Prevent multiple concurrent fetch operations
        guard !isLoadingLibrary else { return }
        isLoadingLibrary = true
        // In previews or very early startup, SwiftData might not be ready yet.
        // Avoid touching the container until it's initialized to prevent fatalError.
        if !swiftDataController.isLoaded {
            if ProcessInfo.isPreview {
                // Provide preview data so Library previews are not empty
                self.audiobooks = [
                    PreviewContent.audiobook(title: "Dune", author: "Frank Herbert"),
                    PreviewContent.audiobook(title: "The Hobbit", author: "J.R.R. Tolkien"),
                    PreviewContent.audiobookLong()
                ]
            }
            // Defer real fetch until the container finishes loading,
            // then process any pending imports as part of that fetch.
            isLoadingLibrary = false
            Task { @MainActor in
                await self.swiftDataController.whenLoaded()
                self.fetchAudiobooks()
            }
            return
        }
        let context = swiftDataController.context
            let descriptor = FetchDescriptor<AudiobookModel>(
                sortBy: [
                    SortDescriptor(\.lastPlayed, order: .reverse),
                    SortDescriptor(\.dateAdded, order: .reverse)
                ]
            )
        do {
            let fetched = try context.fetch(descriptor)
            // Rows written before paths went relative hold a container-absolute path, which a
            // reinstall or a restore from backup invalidates. Rewrite them on sight.
            let migrated = fetched.filter { $0.migrateToRelativePath() }.count > 0
            // Books whose file is missing stay in the library. Deleting them silently threw
            // away progress and bookmarks over what is often a recoverable file, and a re-import
            // of the same file now restores the entry instead of duplicating it.
            for book in fetched where !hasFile(book) {
                Log.library.warning("⚠️ AudiobookManager: File missing for '\(book.title ?? "Unknown")'")
            }
            let valid = fetched
            if migrated {
                do { try context.save() } catch {
                    Log.library.error("❌ AudiobookManager: Failed to save migrated paths: \(error)")
                }
            }
            self.audiobooks = valid
            self.isLoadingLibrary = false
            SpotlightIndex.reindex(valid.map {
                (id: $0.id, title: $0.title ?? AudiobookModel.unknownTitle, author: $0.author ?? AudiobookModel.unknownAuthor)
            })
            self.processPendingImports()
            // The one funnel every library mutation goes through — import, delete, rename,
            // mark as read, new cover — so the watch hears about all of them from here.
            WatchSyncService.shared.pushSnapshot()
        } catch {
            Log.library.error("❌ AudiobookManager: Failed to fetch audiobooks: \(error)")
            self.isLoadingLibrary = false
        }
    }
    
    /// Whether the audio this entry names is on disk right now.
    func hasFile(_ audiobook: AudiobookModel) -> Bool {
        guard let fileURL = audiobook.resolvedFileURL else { return false }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
}
