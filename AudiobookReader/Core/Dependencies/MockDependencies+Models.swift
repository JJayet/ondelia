import Foundation
import SwiftUI
import SwiftData

// MARK: - Core Data Extensions for Previews
extension AudiobookModel {
    static func preview(
        title: String = "The Art of War",
        author: String = "Sun Tzu", 
        narrator: String = "Derek Jacobi",
        duration: TimeInterval = 3600.0,
        currentPosition: TimeInterval = 450.0,
        isFinished: Bool = false
    ) -> AudiobookModel {
        let audiobook = AudiobookModel(
            title: title,
            author: author,
            narrator: narrator,
            duration: duration,
            currentPosition: currentPosition,
            isFinished: isFinished,
            dateAdded: Date(),
            lastPlayed: Date().addingTimeInterval(-3600)
        )
        
        // Create mock cover image data
        if let mockImage = createMockCoverImage(title: title) {
            audiobook.coverImageData = mockImage
        }
        
        // Create sample chapters
        let chapter1 = ChapterModel(
            title: "Chapter 1: Introduction",
            chapterNumber: 1,
            startTime: 0,
            endTime: 1800
        )
        chapter1.audiobook = audiobook
        
        let chapter2 = ChapterModel(
            title: "Chapter 2: Planning",
            chapterNumber: 2,
            startTime: 1800,
            endTime: 3600
        )
        chapter2.audiobook = audiobook
        
        audiobook.chapters = [chapter1, chapter2]
        
        return audiobook
    }
    
    private static func createMockCoverImage(title: String) -> Data? {
        let size = CGSize(width: 300, height: 300)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let image = renderer.image { context in
            // Create gradient background
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                    colors: [UIColor.systemBlue.cgColor, UIColor.systemPurple.cgColor] as CFArray,
                                    locations: [0.0, 1.0])!
            
            context.cgContext.drawLinearGradient(gradient,
                                               start: CGPoint(x: 0, y: 0),
                                               end: CGPoint(x: size.width, y: size.height),
                                               options: [])
            
            // Add book icon
            let bookIcon = UIImage(systemName: "book.closed.fill")
            let iconSize = CGSize(width: 80, height: 80)
            let iconRect = CGRect(x: (size.width - iconSize.width) / 2,
                                y: (size.height - iconSize.height) / 2 - 20,
                                width: iconSize.width,
                                height: iconSize.height)
            
            bookIcon?.withTintColor(.white).draw(in: iconRect)
            
            // Add title text
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .medium),
                .foregroundColor: UIColor.white
            ]
            
            let titleSize = title.size(withAttributes: attributes)
            let titleRect = CGRect(x: (size.width - titleSize.width) / 2,
                                 y: iconRect.maxY + 10,
                                 width: titleSize.width,
                                 height: titleSize.height)
            
            title.draw(in: titleRect, withAttributes: attributes)
        }
        
        return image.pngData()
    }
}

extension ChapterModel {
    static func preview(
        title: String = "Chapter 1: Introduction",
        chapterNumber: Int = 1,
        startTime: TimeInterval = 0,
        endTime: TimeInterval = 1800
    ) -> ChapterModel {
        return ChapterModel(
            title: title,
            chapterNumber: Int16(chapterNumber),
            startTime: startTime,
            endTime: endTime
        )
    }
}

extension BookmarkModel {
    static func preview(
        title: String = "Important Quote",
        note: String? = "This is a really insightful passage",
        timestamp: TimeInterval = 300.0
    ) -> BookmarkModel {
        return BookmarkModel(
            title: title,
            note: note,
            timestamp: timestamp,
            dateCreated: Date()
        )
    }
}
