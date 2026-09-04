import UIKit

/// Decoded covers, kept between row rebuilds.
///
/// `UIImage(data:)` decodes the JPEG every time a row body runs, and a scrolling library runs
/// them constantly. `NSCache` drops its contents under memory pressure on its own, so nothing
/// here has to be sized or evicted by hand.
@MainActor
enum CoverImageCache {
    private static let cache = NSCache<NSUUID, UIImage>()

    static func image(for audiobook: AudiobookModel?) -> UIImage? {
        guard let audiobook else { return nil }
        let key = audiobook.id as NSUUID
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = audiobook.coverImageData, let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Call after writing `coverImageData`, or the old cover keeps being drawn.
    static func invalidate(_ audiobook: AudiobookModel) {
        cache.removeObject(forKey: audiobook.id as NSUUID)
    }
}
