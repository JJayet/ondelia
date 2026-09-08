import Foundation
import SwiftData

// Every stored property is optional or has a default, and nothing is `.unique`: CloudKit sync
// requires both. Uniqueness of `id` is kept by the code that creates rows, not by the store.
@Model
final class AudiobookModel {
    var id: UUID = UUID()
    var title: String?
    var author: String?
    var narrator: String?
    var fileURL: String?
    var duration: Double = 0
    var currentPosition: Double = 0
    var isFinished: Bool = false
    /// Covers are the only large blob on this row; external storage keeps them out of the
    /// row itself so a library fetch does not drag every JPEG into memory.
    @Attribute(.externalStorage) var coverImageData: Data?
    var dateAdded: Date = Date()
    var lastPlayed: Date = Date.distantPast
    /// Playback speed remembered for this book. Optional so adding it never blocks the store
    /// from opening; read it through `speed`, which supplies the 1.0 default.
    var playbackSpeed: Double?
    /// When `currentPosition` was last written, on whichever device wrote it. Optional so
    /// adding it never blocks the store from opening; nil means "older than the watch sync",
    /// which loses every last-write-wins comparison.
    var positionUpdatedAt: Date?
    /// Hardcover book this one is linked to, nil until it is matched. Optional so the store
    /// keeps opening for libraries written before the integration existed.
    var hardcover: HardcoverLink?
    
    // CloudKit refuses non-optional relationships ("requires that all relationships be
    // optional"), so the stored arrays are optional, kept under their original store names.
    // The non-optional wrappers are what the rest of the app reads and writes.
    @Relationship(deleteRule: .cascade, originalName: "bookmarks", inverse: \BookmarkModel.audiobook)
    var storedBookmarks: [BookmarkModel]? = []
    var bookmarks: [BookmarkModel] {
        get { storedBookmarks ?? [] }
        set { storedBookmarks = newValue }
    }

    @Relationship(deleteRule: .cascade, originalName: "chapters", inverse: \ChapterModel.audiobook)
    var storedChapters: [ChapterModel]? = []
    var chapters: [ChapterModel] {
        get { storedChapters ?? [] }
        set { storedChapters = newValue }
    }

    /// The relationship is a set with no order of its own, so every reader needs this and
    /// three of them used to sort it themselves.
    var sortedChapters: [ChapterModel] {
        chapters.sorted { $0.chapterNumber < $1.chapterNumber }
    }

    @Relationship(deleteRule: .cascade, originalName: "transcriptions", inverse: \ChapterTranscriptionModel.audiobook)
    var storedTranscriptions: [ChapterTranscriptionModel]? = []
    var transcriptions: [ChapterTranscriptionModel] {
        get { storedTranscriptions ?? [] }
        set { storedTranscriptions = newValue }
    }
    
    init(
        id: UUID = UUID(),
        title: String? = nil,
        author: String? = nil,
        narrator: String? = nil,
        fileURL: String? = nil,
        duration: Double = 0.0,
        currentPosition: Double = 0.0,
        isFinished: Bool = false,
        coverImageData: Data? = nil,
        dateAdded: Date = Date(),
        lastPlayed: Date = Date.distantPast,
        playbackSpeed: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.narrator = narrator
        self.fileURL = fileURL
        self.duration = duration
        self.currentPosition = currentPosition
        self.isFinished = isFinished
        self.coverImageData = coverImageData
        self.dateAdded = dateAdded
        self.lastPlayed = lastPlayed
        self.playbackSpeed = playbackSpeed
    }

    /// Speed this book plays at, 1.0 until the listener changes it.
    var speed: Float {
        get { playbackSpeed.map(Float.init) ?? 1.0 }
        set { playbackSpeed = Double(newValue) }
    }

    /// How far through the book the listener is, 0...1. Sorting and progress bars want this
    /// rather than `currentPosition`, which makes a long book at 3% outrank a short one at 95%.
    var progressFraction: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentPosition / duration, 0), 1)
    }
}