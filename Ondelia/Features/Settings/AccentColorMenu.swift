import SwiftUI

/// The accent color as a swatch; the menu shows each color beside its name.
struct AccentColorMenu: View {
    private let themeManager = ThemeManager.shared

    var body: some View {
        Menu {
            Picker(
                NSLocalizedString("Accent Color", comment: "Accent color setting label"),
                selection: Binding(
                    get: { themeManager.accentColor },
                    set: { themeManager.setAccentColor($0) }
                )
            ) {
                ForEach(AccentColor.allCases, id: \.rawValue) { color in
                    Label {
                        Text(color.displayName)
                    } icon: {
                        Image(size: CGSize(width: 18, height: 18)) { context in
                            context.fill(
                                Path(ellipseIn: CGRect(x: 0, y: 0, width: 18, height: 18)),
                                with: .color(color.color)
                            )
                        }
                        .renderingMode(.original)
                    }
                    .tag(color)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(themeManager.accentColor.color)
                    .frame(width: 18, height: 18)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(NSLocalizedString("Accent Color", comment: "Accent color setting label"))
        .accessibilityValue(themeManager.accentColor.displayName)
    }
}
