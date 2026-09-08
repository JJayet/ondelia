import UIKit

/// Decoded covers, kept between row rebuilds.
///
/// `UIImage(data:)` decodes the JPEG every time a row body runs, and a scrolling library runs
/// them constantly. Covers are stored at `UIImage.coverMaxPixels`, so one decoded cover is
/// ~4 MiB of RGBA: an unbounded cache pushed a scrolled library into hundreds of megabytes and
/// got the app killed by jetsam. `totalCostLimit` caps that, and `NSCache` still drops
/// everything under memory pressure on its own.
@MainActor
enum CoverImageCache {
    /// Room for roughly a dozen decoded 1024 px covers — a full grid screen, plus the player.
    private static let memoryLimit = 48 * 1024 * 1024

    private static let cache: NSCache<NSUUID, UIImage> = {
        let cache = NSCache<NSUUID, UIImage>()
        cache.totalCostLimit = memoryLimit
        return cache
    }()

    static func image(for audiobook: AudiobookModel?) -> UIImage? {
        guard let audiobook else { return nil }
        let key = audiobook.id as NSUUID
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = audiobook.coverImageData, let image = UIImage(data: data) else { return nil }
        // ponytail: one full-size tier, so a long scroll re-decodes evicted covers. Add a
        // thumbnail tier keyed by draw size if that decode shows up as scrolling jank.
        cache.setObject(image, forKey: key, cost: image.decodedByteCount)
        return image
    }

    /// Call after writing `coverImageData`, or the old cover keeps being drawn — and, with it,
    /// the tint every screen the book appears on is painted with.
    static func invalidate(_ audiobook: AudiobookModel) {
        cache.removeObject(forKey: audiobook.id as NSUUID)
        CoverTintCache.invalidate(audiobook)
    }
}

private extension UIImage {
    /// What the decoded bitmap costs, for `NSCache` accounting. Falls back to the pixel count at
    /// 4 bytes per pixel when there is no `CGImage` to measure.
    var decodedByteCount: Int {
        guard let cgImage else {
            return Int(size.width * scale) * Int(size.height * scale) * 4
        }
        return cgImage.bytesPerRow * cgImage.height
    }
}
