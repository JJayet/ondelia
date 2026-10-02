import Foundation

/// What a Merge keeps of the listener's state. Each source becomes one chapter of the merged
/// audiobook, so everything measured on a source's own timeline moves by that chapter's start.
///
/// The listening log is left as it is: it is append-only, and the sources' sessions keep their
/// own ids. The Hardcover link is dropped, since the merged audiobook is no source's edition.
extension AudiobookManager {
    /// The furthest listened point across `sources`, on the merged timeline, and whether every
    /// source was Finished. `chapters[i]` is the chapter `sources[i]` became.
    static func mergedProgress(
        of sources: [AudiobookModel],
        chapters: [FolderChapter]
    ) -> (position: TimeInterval, finished: Bool) {
        let pairs = zip(sources, chapters)
        let position = pairs
            .filter { source, _ in source.isFinished || source.currentPosition > 0 }
            .map { source, chapter in
                chapter.startTimeInBook + (source.isFinished ? chapter.duration : min(source.currentPosition, chapter.duration))
            }
            .max() ?? 0
        return (position, !sources.isEmpty && sources.allSatisfy(\.isFinished))
    }

    /// `ids` with every one of `sourceIDs` swapped for `mergedID`, once, in the first slot any
    /// of them held. Unchanged when none of them is there.
    static func replacing(_ sourceIDs: Set<UUID>, with mergedID: UUID, in ids: [UUID]) -> [UUID] {
        var placed = false
        return ids.compactMap { id in
            guard sourceIDs.contains(id) || id == mergedID else { return id }
            defer { placed = true }
            return placed ? nil : mergedID
        }
    }

    /// Re-points the sources' bookmarks at `merged`. Done before the sources are deleted, which
    /// would otherwise cascade to them.
    func moveBookmarks(from sources: [AudiobookModel], chapters: [FolderChapter], onto merged: AudiobookModel) {
        for (source, chapter) in zip(sources, chapters) {
            for bookmark in Array(source.bookmarks) {
                bookmark.timestamp += chapter.startTimeInBook
                bookmark.audiobook = merged
            }
        }
    }

    /// `merged` takes the first source's place in every Collection and in Up Next. Idempotent,
    /// so a merge that already synced from another device can run it again: Up Next is per
    /// device and never synced.
    func replaceInCollectionsAndQueue(_ sources: [AudiobookModel], with merged: AudiobookModel) {
        let sourceIDs = Set(sources.map(\.id))
        var changed = false
        for collection in collections {
            let replaced = Self.replacing(sourceIDs, with: merged.id, in: collection.bookIDs)
            guard replaced != collection.bookIDs else { continue }
            collection.bookIDs = replaced
            changed = true
        }
        if changed {
            swiftDataController.save()
            fetchCollections()
        }
        PlayQueue.shared.replace(sourceIDs, with: merged.id)
    }
}
