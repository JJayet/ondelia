import Foundation
import AVFoundation

@MainActor
class AudioMetadataLoader: ObservableObject {
    static let shared = AudioMetadataLoader()
    
    private init() {}
    
    /// Load metadata using modern async/await pattern
    func loadMetadata(from asset: AVAsset) async throws -> AudioMetadata {
        // Load duration
        let duration = try await asset.load(.duration)
        
        // Load metadata
        let metadata = try await asset.load(.metadata)
        
        var title: String?
        var artist: String?
        var artwork: Data?
        
        for item in metadata {
            guard let key = item.commonKey else { continue }
            
            switch key {
            case .commonKeyTitle:
                title = try await item.load(.stringValue)
            case .commonKeyArtist:
                artist = try await item.load(.stringValue)
            case .commonKeyArtwork:
                artwork = try await item.load(.dataValue)
            default:
                break
            }
        }
        
        return AudioMetadata(
            duration: duration.seconds,
            title: title,
            artist: artist,
            artwork: artwork
        )
    }
}

struct AudioMetadata {
    let duration: TimeInterval
    let title: String?
    let artist: String?
    let artwork: Data?
}