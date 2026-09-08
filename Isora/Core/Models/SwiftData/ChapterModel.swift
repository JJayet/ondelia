import Foundation
import SwiftData

@Model
final class ChapterModel {
    var id: UUID = UUID()
    var title: String?
    var chapterNumber: Int16 = 0
    var startTime: Double = 0
    var endTime: Double = 0
    
    var audiobook: AudiobookModel?
    
    init(
        id: UUID = UUID(),
        title: String? = nil,
        chapterNumber: Int16 = 0,
        startTime: Double = 0.0,
        endTime: Double = 0.0
    ) {
        self.id = id
        self.title = title
        self.chapterNumber = chapterNumber
        self.startTime = startTime
        self.endTime = endTime
    }
}