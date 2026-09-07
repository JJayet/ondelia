import UIKit

/// A fresh `UIImpactFeedbackGenerator` fired once and dropped can go silent: the Taptic Engine
/// plays the impact asynchronously, and a generator deallocated (or left unprepared) before that
/// completes may not play at all — worse right after `prepare()`, and worse still when the tap
/// also tears down a sheet in the same run loop turn (e.g. chapter/bookmark rows dismiss on tap).
/// One prepared generator per style, kept alive for the app's lifetime, avoids both problems.
@MainActor
private enum HapticGenerators {
    static var generators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]

    static func generator(for style: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        if let existing = generators[style] { return existing }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generators[style] = generator
        return generator
    }
}

/// Emit feedback only for explicit UI actions, never for remote commands or engine updates.
@MainActor
@discardableResult
func withHapticFeedback<T>(
    _ intensity: UIImpactFeedbackGenerator.FeedbackStyle = .light,
    _ action: () -> T
) -> T {
    let impact = HapticGenerators.generator(for: intensity)
    impact.impactOccurred()
    impact.prepare()
    return action()
}
