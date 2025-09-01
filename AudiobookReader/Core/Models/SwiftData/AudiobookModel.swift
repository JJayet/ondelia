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
        lastPlayed: Date = Date.distantPast
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
    }
}