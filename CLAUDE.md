# AudiobookReader iOS Project - Claude Development Instructions

## Project Overview
This is an iOS audiobook reader application built with SwiftUI. The app features audio playback, live activities, widgets, and transcription capabilities.

## iOS Development Settings

### Xcode Build Configuration
- **Always use iPhone 16** as the simulator destination for builds
- Build command: `xcodebuild -project AudiobookReader.xcodeproj -scheme AudiobookReader -destination 'platform=iOS Simulator,name=iPhone 16' build`
- Test command: `xcodebuild -project AudiobookReader.xcodeproj -scheme AudiobookReader -destination 'platform=iOS Simulator,name=iPhone 16' test`

### Project Structure
```
AudiobookReader/
├── App/                    # Main app entry point
├── Core/                   # Core functionality and managers
│   ├── Managers/          # GlobalAudioManager, etc.
│   └── Models/            # Data models
├── Features/              # Feature-specific modules
│   ├── Player/           # Audio player UI and logic
│   ├── Widgets/          # iOS widgets
│   └── LiveActivities/   # Live activities implementation
└── Resources/            # Assets, localization, etc.
```

### Key Components
- **PlayerView.swift**: Main audio player interface with miniplayer functionality
- **GlobalAudioManager**: Handles audio playback state management
- **Live Activities**: Shows now playing info on lock screen
- **Widgets**: Home screen widgets for quick access

### Development Guidelines
1. Always test builds before committing changes
2. Use iPhone 16 simulator for consistent testing
3. Follow SwiftUI best practices for UI development
4. Maintain proper separation between UI and business logic

## iOS 26 Visual Effects

### Target Platform
**This project exclusively targets iOS 26+. No backward compatibility needed.**

### Liquid Glass Effects
This project uses the new Liquid Glass design language introduced in iOS 26. Always use the proper iOS 26 glass effects:

#### Primary Glass Effect Implementation
```swift
// Use the new glassEffect modifier for iOS 26
.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))

// For interactive elements, use the interactive variant
.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 24))
```

#### Glass Container for Grouped Elements
```swift
GlassEffectContainer {
    // Multiple glass elements here share the same visual context
    controlPanel
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    
    miniPlayer
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12))
}
```

#### Sheet Presentations with Liquid Glass
```swift
.sheet(isPresented: $showSheet) {
    SheetContent()
        .presentationDetents([.medium, .large])
        .navigationTransition(.zoom(sourceID: "sourceButton"))
}
```

### Visual Design Principles
- UI elements should "float, breathe, and interact with light"
- Use `.interactive()` for user-interactive glass elements
- Group related glass elements in containers for visual consistency
- Avoid custom `presentationBackground()` modifiers with glass sheets
- Glass effects automatically adapt to underlying content
- **Never use .ultraThinMaterial** - always use proper glassEffect modifiers

### Testing Commands
- Build: Use the command above with iPhone 16 destination
- Run tests: Replace `build` with `test` in the build command
- Clean build: Add `clean` before `build` in the command

## Recent Changes
- Implemented drag-to-minimize functionality for PlayerView
- Updated background layer to use 70% height with full width
- Reduced padding constraints for full-width usage
- Added miniplayer mode with tap-to-expand functionality