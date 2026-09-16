import SwiftUI

/// Goal ring with the streak count in the middle.
struct StreakRing: View {
    let progress: Double
    let days: Int
    var lineWidth: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var numberSize: CGFloat = 19

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.2), value: progress)

            VStack(spacing: 1) {
                Text(verbatim: "\(days)")
                    .font(.system(size: numberSize, weight: .bold))
                Text(NSLocalizedString("days", comment: "Days unit for stat card").uppercased())
                    .font(.system(size: numberSize * 0.4, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(lineWidth / 2)
    }
}
