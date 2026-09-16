import SwiftUI
import UIKit

// MARK: - Cover tint
//
// The design draws every screen on two blurred colour blobs taken from the book's cover. The
// average colour of a cover is usually muddy, so each sample is pushed back up in saturation
// and clamped in brightness — otherwise a dark cover paints a black blob on a black background.

/// Two colours sampled from a cover, top-left and bottom-right.
struct CoverTint: Equatable {
    var primary: Color
    var secondary: Color

    static let fallback = CoverTint(
        primary: Color(red: 0.36, green: 0.89, blue: 0.93),
        secondary: Color(red: 0.18, green: 0.16, blue: 0.55)
    )
}

@MainActor
enum CoverTintCache {
    /// Cap on remembered tints. A tint is two colours and cheap to sample again, so there is no
    /// reason to hold one per book in a library of any size for the whole run.
    private static let limit = 256

    private static var tints: [UUID: CoverTint] = [:]

    static func tint(for audiobook: AudiobookModel?) -> CoverTint {
        guard let audiobook else { return .fallback }
        if let cached = tints[audiobook.id] { return cached }
        guard let image = CoverImageCache.image(for: audiobook) else { return .fallback }
        let tint = Self.sample(image)
        // ponytail: flushes the whole dictionary at the cap. Swap in an LRU if a huge library
        // makes the re-sampling visible.
        if tints.count >= Self.limit { tints.removeAll() }
        tints[audiobook.id] = tint
        return tint
    }

    static func invalidate(_ audiobook: AudiobookModel) {
        tints.removeValue(forKey: audiobook.id)
    }

    /// Redraws the cover into a 2×2 bitmap and keeps the two opposite corners.
    private static func sample(_ image: UIImage) -> CoverTint {
        let size = CGSize(width: 2, height: 2)
        var pixels = [UInt8](repeating: 0, count: 16)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let cgImage = image.cgImage,
              let context = CGContext(
                  data: &pixels,
                  width: 2,
                  height: 2,
                  bitsPerComponent: 8,
                  bytesPerRow: 8,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return .fallback }

        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        return CoverTint(
            primary: vivid(pixels[0], pixels[1], pixels[2]),
            secondary: vivid(pixels[12], pixels[13], pixels[14])
        )
    }

    private static func vivid(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Color {
        let ui = UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard ui.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return CoverTint.fallback.primary
        }
        return Color(
            hue: hue,
            saturation: min(max(saturation, 0.55), 1),
            brightness: min(max(brightness, 0.42), 0.82)
        )
    }
}

// MARK: - Tinted background

/// The canvas every redesigned screen sits on: a near-black (or system) ground, two blurred
/// colour blobs from the cover, and a scrim so text keeps its contrast over both.
struct TintedBackground: View {
    var tint: CoverTint = .fallback
    /// Player and book detail push the blobs harder than the library does.
    var intensity: Double = 1

    @Environment(\.colorScheme) private var colorScheme

    private var ground: Color {
        colorScheme == .dark ? Color(red: 0.027, green: 0.031, blue: 0.039) : Color(.systemBackground)
    }

    var body: some View {
        ZStack {
            ground
            GeometryReader { geometry in
                let side = geometry.size.width * 1.1
                Circle()
                    .fill(tint.primary)
                    .frame(width: side, height: side)
                    .blur(radius: 90)
                    .opacity(0.5 * intensity)
                    .offset(x: -side * 0.32, y: -side * 0.34)
                Circle()
                    .fill(tint.secondary)
                    .frame(width: side, height: side)
                    .blur(radius: 96)
                    .opacity(0.38 * intensity)
                    .offset(x: geometry.size.width - side * 0.62, y: geometry.size.height - side * 0.72)
            }
            LinearGradient(
                colors: [ground.opacity(0.35), ground.opacity(0.86), ground],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Glass card

/// The rim every glass surface in the design carries: a lit top edge in the dark, a plain
/// hairline in the light, where a white rim would be invisible.
private struct GlassRim: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> AnyShapeStyle {
        guard environment.colorScheme == .dark else {
            return AnyShapeStyle(Color.black.opacity(0.07))
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [.white.opacity(0.22), .white.opacity(0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

extension View {
    /// The card every panel in the design uses: system glass, a hairline rim, and the inset
    /// top highlight that makes it read as a lit edge rather than a flat fill.
    func glassCard(cornerRadius: CGFloat = 26) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return glassEffect(.regular, in: shape)
            .overlay { shape.strokeBorder(GlassRim(), lineWidth: 0.5) }
    }

    /// Small glass pill: filter chips, speed, sleep timer, transcript.
    func glassPill(height: CGFloat = 38, tinted: Bool = false) -> some View {
        let shape = Capsule(style: .continuous)
        return font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16)
            .frame(height: height)
            .glassEffect(.regular, in: shape)
            .overlay { shape.strokeBorder(tinted ? AnyShapeStyle(.tint.opacity(0.35)) : AnyShapeStyle(GlassRim()), lineWidth: 0.5) }
    }
}

// MARK: - Type

/// The uppercase, letter-spaced label that opens every section in the design.
struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Thin capsule progress line — the design never uses the stock `ProgressView` bar.
struct ProgressLine: View {
    let value: Double
    var height: CGFloat = 4
    /// nil follows the view's tint, which is the theme's accent. `Color.accentColor` does
    /// not: it reads the asset catalogue, not `.tint()`.
    var color: Color?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.tint))
                    .frame(width: geometry.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: height)
    }
}
