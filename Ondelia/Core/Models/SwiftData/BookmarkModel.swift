import Foundation
import SwiftData

@Model
final class BookmarkModel {
    var id: UUID = UUID()
    var title: String?
    var note: String?
    var timestamp: Double = 0
    var dateCreated: Date?
    
    var audiobook: AudiobookModel?
    
    init(
        id: UUID = UUID(),
        title: String? = nil,
        note: String? = nil,
        timestamp: Double = 0.0,
        dateCreated: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.timestamp = timestamp
        self.dateCreated = dateCreated
    }
}