import Foundation
import SwiftData

@Model
final class ChapterTranscriptionModel {
    var id: UUID
    var chapterIndex: Int16
    var transcriptionText: String?
    var translatedText: String?
    var language: String?
    var translationLanguage: String?
    var transcriptionEngine: String?
    var segmentsData: Data?
    var dateCreated: Date?
    
    var audiobook: AudiobookModel?
    
    init(
        id: UUID = UUID(),
        chapterIndex: Int16 = 0,
        transcriptionText: String? = nil,
        translatedText: String? = nil,
        language: String? = nil,
        translationLanguage: String? = nil,
        transcriptionEngine: String? = nil,
        segmentsData: Data? = nil,
        dateCreated: Date? = nil
    ) {
        self.id = id
        self.chapterIndex = chapterIndex
        self.transcriptionText = transcriptionText
        self.translatedText = translatedText
        self.language = language
        self.translationLanguage = translationLanguage
        self.transcriptionEngine = transcriptionEngine
        self.segmentsData = segmentsData
        self.dateCreated = dateCreated
    }
}