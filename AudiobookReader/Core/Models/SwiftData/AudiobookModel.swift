import Foundation
import SwiftData

@Model
final class AudiobookModel {
    var id: UUID
    var title: String?
    var author: String?
    var narrator: String?
    var fileURL: String?
    var duration: Double
    var currentPosition: Double
    var isFinished: Bool
    var coverImageData: Data?
    var dateAdded: Date
    var lastPlayed: Date
    /// Playback speed remembered for this book. Optional so adding it never blocks the store
    /// from opening; read it through `speed`, which supplies the 1.0 default.
    var playbackSpeed: Double?
    
    @Relationship(deleteRule: .cascade, inverse: \BookmarkModel.audiobook)
    var bookmarks: [BookmarkModel] = []
    
    @Relationship(deleteRule: .cascade, inverse: \ChapterModel.audiobook)
    var chapters: [ChapterModel] = []
    
    @Relationship(deleteRule: .cascade, inverse: \ChapterTranscriptionModel.audiobook)
    var transcriptions: [ChapterTranscriptionModel] = []
    
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