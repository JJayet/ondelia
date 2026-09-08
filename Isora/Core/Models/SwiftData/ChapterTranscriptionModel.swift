import Foundation
import SwiftData

@Model
final class ChapterTranscriptionModel {
    var id: UUID = UUID()
    var chapterIndex: Int16 = 0
    var transcriptionText: String?
    var language: String?
    var transcriptionEngine: String?
    var segmentsData: Data?
    var dateCreated: Date?
    
    var audiobook: AudiobookModel?
    
    init(
        id: UUID = UUID(),
        chapterIndex: Int16 = 0,
        transcriptionText: String? = nil,
        language: String? = nil,
        transcriptionEngine: String? = nil,
        segmentsData: Data? = nil,
        dateCreated: Date? = nil
    ) {
        self.id = id
        self.chapterIndex = chapterIndex
        self.transcriptionText = transcriptionText
        self.language = language
        self.transcriptionEngine = transcriptionEngine
        self.segmentsData = segmentsData
        self.dateCreated = dateCreated
    }
}