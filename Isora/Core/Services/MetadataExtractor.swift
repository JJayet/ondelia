import Foundation
import AVFoundation
import UIKit

struct AudiobookMetadata {
    let title: String
    let author: String
    let narrator: String?
    let duration: TimeInterval
    let coverImage: UIImage?
    /// The album the file belongs to. For a book split into per-chapter files this is the book
    /// title, which is the only place that name survives when the files come from a file provider.
    let album: String?
}

enum MetadataExtractor {
    /// Narrators have no common key. Audible and iTunes write `©nrt`, ID3 taggers use a `TXXX`
    /// frame described "narrator", and most rippers put the narrator in Composer.
    /// ponytail: the composer fallback trusts audiobook tagging habits; a real composer tag on
    /// a music file would land here too.
    static func narratorTag(in metadata: [AVMetadataItem]) async -> String? {
        let explicit = metadata.filter { item in
            let id = item.identifier?.rawValue.lowercased() ?? ""
            let info = (item.extraAttributes?[.info] as? String)?.lowercased() ?? ""
            return id.contains("%a9nrt") || id.contains("narrator") || info.contains("narrator")
        }
        let composer = metadata.filter {
            $0.identifier == .iTunesMetadataComposer || $0.identifier == .id3MetadataComposer
        }
        for item in explicit + composer {
            guard let raw = try? await item.load(.stringValue) else { continue }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    static func extractMetadata(from url: URL) async -> AudiobookMetadata? {
        Log.library.debug("🎵 MetadataExtractor: Starting metadata extraction for: \(url.lastPathComponent)")
        
        // Ensure we have access to the security-scoped resource if needed
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { 
            if hasAccess { 
                url.stopAccessingSecurityScopedResource() 
                Log.library.debug("🔓 MetadataExtractor: Released security-scoped resource access")
            }
        }
        
        let asset = AVURLAsset(url: url)
        
        // Load duration with individual error handling
        Log.library.debug("   Loading duration...")
        let duration: TimeInterval
        do {
            let durationCMTime = try await asset.load(.duration)
            duration = durationCMTime.seconds.isFinite ? durationCMTime.seconds : 0
            Log.library.debug("   Duration loaded: \(duration)s")
        } catch {
            Log.library.debug("   ⚠️ Could not get duration: \(error.localizedDescription)")
            duration = 0
        }
        
        // Load metadata with individual error handling
        Log.library.debug("   Loading metadata...")
        let metadata: [AVMetadataItem]
        do {
            metadata = try await asset.load(.metadata)
            Log.library.debug("   Found \(metadata.count) metadata items")
        } catch {
            Log.library.debug("   ⚠️ Could not load metadata: \(error.localizedDescription)")
            metadata = []
        }
            
            var title = url.deletingPathExtension().lastPathComponent
            var author = "Unknown Author"
            var narrator: String?
            var coverImage: UIImage?
            var album: String?
            
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
                        Log.library.debug("   ⚠️ Could not load title: \(error.localizedDescription)")
                    }
                case .commonKeyArtist:
                    do {
                        if let artistValue = try await item.load(.stringValue) {
                            author = artistValue
                        }
                    } catch {
                        Log.library.debug("   ⚠️ Could not load artist: \(error.localizedDescription)")
                    }
                case .commonKeyAlbumName:
                    do {
                        if let albumValue = try await item.load(.stringValue) {
                            album = albumValue
                            if title == url.deletingPathExtension().lastPathComponent {
                                title = albumValue
                            }
                        }
                    } catch {
                        Log.library.debug("   ⚠️ Could not load album name: \(error.localizedDescription)")
                    }
                case .commonKeyArtwork:
                    do {
                        if let artworkData = try await item.load(.dataValue) {
                            coverImage = UIImage(data: artworkData)
                        }
                    } catch {
                        Log.library.debug("   ⚠️ Could not load artwork: \(error.localizedDescription)")
                    }
                default:
                    break
                }
            }
            narrator = await narratorTag(in: metadata)
            
        Log.library.debug("✅ MetadataExtractor: Metadata extraction completed:")
        Log.library.debug("   Title: \(title)")
        Log.library.debug("   Author: \(author)")
        Log.library.debug("   Duration: \(duration)s")
        Log.library.debug("   Has cover: \(coverImage != nil)")
        
        return AudiobookMetadata(
            title: title,
            author: author,
            narrator: narrator,
            duration: duration,
            coverImage: coverImage,
            album: album
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
            let locales = try? await asset.load(.availableChapterLocales)
            guard let first = locales?.first else { return [] }

            let chapterMetadata = try await asset.loadChapterMetadataGroups(withTitleLocale: first)
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
            Log.library.debug("Failed to extract chapters: \(error)")
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
