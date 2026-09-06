import SwiftUI

/// The cover, or a waveform placeholder. `CoverArtView` lives in the iOS target only, and this
/// is the whole of what the watch needs from it.
struct WatchCoverView: View {
    let data: Data?
    var side: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: side / 5, style: .continuous)
            .fill(.ultraThinMaterial)
            .frame(width: side, height: side)
            .overlay {
                if let data, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "waveform")
                        .font(.system(size: side / 2.6, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: side / 5, style: .continuous))
    }
}

/// Average colour of a cover, used to tint the play button on the player screen.
///
/// Drawing the image into a one-pixel context *is* the area average, which is why there is no
/// Core Image filter here — and the result is cached, because it is asked for on every redraw.
/// Only ever asked for from a view body, so the cache lives on the main actor rather than behind
/// an `@unchecked Sendable` promise nothing enforced.
@MainActor
enum CoverTint {
    private static var cache: [Int: Color?] = [:]

    static func color(for data: Data?) -> Color? {
        guard let data else { return nil }
        let key = data.count &* 31 &+ Int(data.first ?? 0)
        if let hit = cache[key] { return hit }
        let computed = compute(data)
        cache[key] = computed
        return computed
    }

    private static func compute(_ data: Data) -> Color? {
        guard let image = UIImage(data: data)?.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: info
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        // Lifted towards white so a dark cover still reads as a tint on a black watch face.
        let components = pixel.prefix(3).map { min(Double($0) / 255 * 1.35, 1) }
        guard components.count == 3 else { return nil }
        return Color(red: components[0], green: components[1], blue: components[2])
    }
}
