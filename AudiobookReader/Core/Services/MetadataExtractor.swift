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
        print("🎵 MetadataExtractor: Starting metadata extraction for: \(url.lastPathComponent)")
        
        // Ensure we have access to the security-scoped resource if needed
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { 
            if hasAccess { 
                url.stopAccessingSecurityScopedResource() 
                print("🔓 MetadataExtractor: Released security-scoped resource access")
            }
        }
        
        let asset = AVURLAsset(url: url)
        
        // Load duration with individual error handling
        print("   Loading duration...")
        let duration: TimeInterval
        do {
            let durationCMTime = try await asset.load(.duration)
            duration = durationCMTime.seconds.isFinite ? durationCMTime.seconds : 0
            print("   Duration loaded: \(duration)s")
        } catch {
            print("   ⚠️ Could not get duration: \(error.localizedDescription)")
            duration = 0
        }
        
        // Load metadata with individual error handling
        print("   Loading metadata...")
        let metadata: [AVMetadataItem]
        do {
            metadata = try await asset.load(.metadata)
            print("   Found \(metadata.count) metadata items")
        } catch {
            print("   ⚠️ Could not load metadata: \(error.localizedDescription)")
            metadata = []
        }
            
            var title = url.deletingPathExtension().lastPathComponent
            var author = "Unknown Author"
            var narrator: String?
            var coverImage: UIImage?
            
            // Process metadata items with individual error handling
            for item in metadata {
                guard let key = item.commonKey else { continue }
                
                switch key {
                case .commonKeyTitle:
                    do {
                        if let titleValue = try await item.load(.stringValue) {
                            title = titleValue
                        }
                    } catch {
                        print("   ⚠️ Could not load title: \(error.localizedDescription)")
                    }
                case .commonKeyArtist:
                    do {
                        if let artistValue = try await item.load(.stringValue) {
                            author = artistValue
                        }
                    } catch {
                        print("   ⚠️ Could not load artist: \(error.localizedDescription)")
                    }
                case .commonKeyAlbumName:
                    do {
                        if let albumValue = try await item.load(.stringValue), title == url.deletingPathExtension().lastPathComponent {
                            title = albumValue
                        }
                    } catch {
                        print("   ⚠️ Could not load album name: \(error.localizedDescription)")
                    }
                case .commonKeyArtwork:
                    do {
                        if let artworkData = try await item.load(.dataValue) {
                            coverImage = UIImage(data: artworkData)
                        }
                    } catch {
                        print("   ⚠️ Could not load artwork: \(error.localizedDescription)")
                    }
                default:
                    break
                }
                
                // Check for narrator in additional metadata with error handling
                if let identifier = item.identifier?.rawValue {
                    if identifier.lowercased().contains("narrator") {
                        do {
                            narrator = try await item.load(.stringValue)
                        } catch {
                            print("   ⚠️ Could not load narrator: \(error.localizedDescription)")
                        }
                    }
                }
            }
            
        print("✅ MetadataExtractor: Metadata extraction completed:")
        print("   Title: \(title)")
        print("   Author: \(author)")
        print("   Duration: \(duration)s")
        print("   Has cover: \(coverImage != nil)")
        
        return AudiobookMetadata(
            title: title,
            author: author,
            narrator: narrator,
            duration: duration,
            coverImage: coverImage
        )
    }
    
    static func extractChapters(from url: URL) async -> [ChapterInfo] {
        // Ensure we have access to the security-scoped resource if needed
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { 
            if hasAccess { 
                url.stopAccessingSecurityScopedResource() 
            }
        }
        
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
