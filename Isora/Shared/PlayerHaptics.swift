import UIKit

/// Emit feedback only for explicit UI actions, never for remote commands or engine updates.
@MainActor
@discardableResult
func withHapticFeedback<T>(
    _ intensity: UIImpactFeedbackGenerator.FeedbackStyle = .light,
    _ action: () -> T
) -> T {
    let impact = UIImpactFeedbackGenerator(style: intensity)
    impact.prepare()
    impact.impactOccurred()
    return action()
}
