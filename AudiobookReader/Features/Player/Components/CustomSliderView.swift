import SwiftUI

struct PlayerProgressSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onEditingChanged: (Bool) -> Void
    var body: some View {
        Slider(value: $value, in: range, onEditingChanged: onEditingChanged)
            .tint(.accentColor)
            .frame(minHeight: 44)
            .accessibilityLabel(NSLocalizedString("Playback position", comment: "Player progress slider label"))
            .accessibilityValue(formatAccessibilityValue(value))
            .accessibilityIdentifier(AccessibilityIdentifiers.Player.progressSlider)
    }

    private func formatAccessibilityValue(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(
            format: NSLocalizedString("%d minutes, %d seconds", comment: "Accessible playback time"),
            minutes,
            remainingSeconds
        )
    }
}
