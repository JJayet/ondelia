import Foundation
import AVFoundation
import UIKit

struct AudiobookMetadata {
    let title: String
    let author: String
    let narrator: String?
    let duration: TimeInterval
    let coverImage: UIImage?
}

class MetadataExtractor {
    static func extractMetadata(from url: URL) async -> AudiobookMetadata? {
        let asset = AVAsset(url: url)
        
        do {
            let duration = try await asset.load(.duration).seconds
            let metadata = try await asset.load(.metadata)
            
            var title = url.deletingPathExtension().lastPathComponent
            var author = "Unknown Author"
            var narrator: String?
            var coverImage: UIImage?
            
            for item in metadata {
                guard let key = item.commonKey else { continue }
                
                switch key {
                case .commonKeyTitle:
                    if let titleValue = try await item.load(.stringValue) {
                        title = titleValue
                    }
                case .commonKeyArtist:
                    if let artistValue = try await item.load(.stringValue) {
                        author = artistValue
                    }
                case .commonKeyAlbumName:
                    if let albumValue = try await item.load(.stringValue), title == url.deletingPathExtension().lastPathComponent {
                        title = albumValue
                    }
                case .commonKeyArtwork:
                    if let artworkData = try await item.load(.dataValue) {
                        coverImage = UIImage(data: artworkData)
                    }
                default:
                    break
                }
                
                // Check for narrator in additional metadata
                if let identifier = item.identifier?.rawValue {
                    if identifier.lowercased().contains("narrator") {
                        narrator = try? await item.load(.stringValue)
                    }
                }
            }
            
            return AudiobookMetadata(
                title: title,
                author: author,
                narrator: narrator,
                duration: duration.isFinite ? duration : 0,
                coverImage: coverImage
            )
            
        } catch {
            print("Failed to extract metadata: \(error)")
            return nil
        }
    }
    
    static func extractChapters(from url: URL) async -> [ChapterInfo] {
        let asset = AVURLAsset(url: url)
        
        do {
            let chapterMetadata = try await asset.loadChapterMetadataGroups(withTitleLocale: .current)
            var chapters: [ChapterInfo] = []
            
            for (index, chapterGroup) in chapterMetadata.enumerated() {
                let timeRange = chapterGroup.timeRange
                let startTime = timeRange.start.seconds
                let endTime = timeRange.end.seconds
                
                var chapterTitle = "Chapter \(index + 1)"
                
                for item in chapterGroup.items {
                    if let key = item.commonKey, key == .commonKeyTitle {
                        if let titleValue = try? await item.load(.stringValue) {
                            chapterTitle = titleValue
                        }
                    }
                }
                
                let chapter = ChapterInfo(
                    title: chapterTitle,
                    startTime: startTime.isFinite ? startTime : 0,
                    endTime: endTime.isFinite ? endTime : 0,
                    chapterNumber: index + 1
                )
                chapters.append(chapter)
            }
            
            return chapters
            
        } catch {
            print("Failed to extract chapters: \(error)")
            return []
        }
    }
}

struct ChapterInfo {
    let title: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let chapterNumber: Int
}
