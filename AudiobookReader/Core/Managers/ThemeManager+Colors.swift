import SwiftUI

// MARK: - Theme Environment
struct ThemeEnvironment: EnvironmentKey {
    @MainActor
    static var defaultValue: ThemeManager { ThemeManager.shared }
}

extension EnvironmentValues {
    var theme: ThemeManager {
        get { self[ThemeEnvironment.self] }
        set { self[ThemeEnvironment.self] = newValue }
    }
}

// MARK: - Custom Colors
extension Color {
    @MainActor static var primaryBackground: Color {
        switch ThemeManager.shared.currentTheme {
        case .sepia:
            // Sepia: warm parchment
            return Color(red: 0.953, green: 0.914, blue: 0.843) // #F3E9D7
        case .dark:
            return Color(red: 0.06, green: 0.06, blue: 0.07)
        case .dim:
            // Dim: softer dark, less contrast than pure dark
            return Color(red: 0.106, green: 0.110, blue: 0.122) // #1B1C1F
        case .light:
            return Color(.systemBackground)
        case .system:
            return Color(.systemBackground)
        }
    }

    // Glass tint to theme materials consistently
    @MainActor static var glassTint: Color {
        switch ThemeManager.shared.currentTheme {
        case .sepia:
            // Warm amber glow over material
            return Color(red: 0.90, green: 0.74, blue: 0.42).opacity(0.10) // #E6BD6B @10%
        case .dim:
            // Slight lift to avoid harsh contrast
            return Color.white.opacity(0.06)
        case .dark:
            return Color.white.opacity(0.04)
        case .light, .system:
            return Color.black.opacity(0.03)
        }
    }
    
    @MainActor static var secondaryBackground: Color {
        switch ThemeManager.shared.currentTheme {
        case .sepia:
            return Color(red: 0.937, green: 0.882, blue: 0.788) // #EFE1C9
        case .dark:
            return Color(red: 0.10, green: 0.10, blue: 0.11)
        case .dim:
            return Color(red: 0.137, green: 0.145, blue: 0.161) // #232529
        case .light:
            return Color(.systemGroupedBackground)
        case .system:
            return Color(.systemGroupedBackground)
        }
    }
    
    @MainActor static var primaryText: Color {
        switch ThemeManager.shared.currentTheme {
        case .sepia:
            return Color(red: 0.243, green: 0.184, blue: 0.118) // #3E2F1E
        case .dark, .dim:
            return Color(red: 0.903, green: 0.909, blue: 0.915) // #E6E7EA
        case .light, .system:
            return Color(.label)
        }
    }
    
    @MainActor static var secondaryText: Color {
        switch ThemeManager.shared.currentTheme {
        case .sepia:
            return Color(red: 0.435, green: 0.353, blue: 0.235) // #6F5A3C
        case .dark, .dim:
            return Color(red: 0.659, green: 0.671, blue: 0.698) // #A8ABB2
        case .light, .system:
            return Color(.secondaryLabel)
        }
    }
}
