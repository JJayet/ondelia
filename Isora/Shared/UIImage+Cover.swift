import UIKit

extension UIImage {
    /// Longest side a stored cover is allowed. The biggest place a cover is drawn is the player
    /// screen at roughly 300 pt, so 1024 px stays crisp on any current display.
    static let coverMaxPixels: CGFloat = 1024

    /// JPEG for `coverImageData`, downsampled first. Every cover write goes through here, so a
    /// 3000 × 3000 photo never reaches the store, the cover cache, the widget file or the
    /// watch — one decoded 3000 px RGBA image alone is ~34 MiB.
    func coverJPEGData(compressionQuality: CGFloat = 0.8) -> Data? {
        let longest = max(size.width, size.height) * scale
        guard longest > Self.coverMaxPixels else { return jpegData(compressionQuality: compressionQuality) }
        let ratio = Self.coverMaxPixels / longest
        let target = CGSize(width: (size.width * scale * ratio).rounded(), height: (size.height * scale * ratio).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: compressionQuality)
    }
}
