import SwiftUI

// MARK: - Dynamic Type Typography System
extension Font {
    // Display fonts for large content
    static var displayLarge: Font {
        .custom("SF Pro Display", size: 57, relativeTo: .largeTitle)
    }
    
    static var displayMedium: Font {
        .custom("SF Pro Display", size: 45, relativeTo: .largeTitle)
    }
    
    static var displaySmall: Font {
        .custom("SF Pro Display", size: 36, relativeTo: .title)
    }
    
    // Headline fonts for section headers
    static var headlineLarge: Font {
        .custom("SF Pro Display", size: 32, relativeTo: .title)
    }
    
    static var headlineMedium: Font {
        .custom("SF Pro Display", size: 28, relativeTo: .title2)
    }
    
    static var headlineSmall: Font {
        .custom("SF Pro Display", size: 24, relativeTo: .title3)
    }
    
    // Title fonts for content headers
    static var titleLarge: Font {
        .custom("SF Pro Text", size: 22, relativeTo: .headline)
    }
    
    static var titleMedium: Font {
        .custom("SF Pro Text", size: 16, relativeTo: .body)
    }
    
    static var titleSmall: Font {
        .custom("SF Pro Text", size: 14, relativeTo: .subheadline)
    }
    
    // Label fonts for UI elements
    static var labelLarge: Font {
        .custom("SF Pro Text", size: 14, relativeTo: .footnote)
    }
    
    static var labelMedium: Font {
        .custom("SF Pro Text", size: 12, relativeTo: .caption)
    }
    
    static var labelSmall: Font {
        .custom("SF Pro Text", size: 11, relativeTo: .caption2)
    }
    
    // Body fonts with enhanced readability
    static var bodyLarge: Font {
        .custom("SF Pro Text", size: 16, relativeTo: .body)
    }
    
    static var bodyMedium: Font {
        .custom("SF Pro Text", size: 14, relativeTo: .callout)
    }
    
    static var bodySmall: Font {
        .custom("SF Pro Text", size: 12, relativeTo: .footnote)
    }
}
