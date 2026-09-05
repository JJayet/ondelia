import SwiftUI

// MARK: - Custom Colors
//
// Only the explicit dark theme needs colours of its own; light and system take the system's,
// which already answer to the viewer's own appearance and contrast settings. The bespoke
// sepia and dim palettes are gone: they were applied in some views and ignored in others.
extension Color {
    @MainActor private static var isDark: Bool {
        ThemeManager.shared.currentTheme == .dark
    }

    @MainActor static var primaryBackground: Color {
        isDark ? Color(red: 0.06, green: 0.06, blue: 0.07) : Color(.systemBackground)
    }

    /// Glass tint, so materials read the same way across the app.
    @MainActor static var glassTint: Color {
        isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.03)
    }

    @MainActor static var secondaryBackground: Color {
        isDark ? Color(red: 0.10, green: 0.10, blue: 0.11) : Color(.systemGroupedBackground)
    }

    @MainActor static var primaryText: Color {
        isDark ? Color(red: 0.903, green: 0.909, blue: 0.915) : Color(.label)
    }

    @MainActor static var secondaryText: Color {
        isDark ? Color(red: 0.659, green: 0.671, blue: 0.698) : Color(.secondaryLabel)
    }
}
