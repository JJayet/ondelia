# AudiobookReader - Technology Stack

## Core Technologies
- **Swift 5.9+**: Primary programming language
- **SwiftUI**: Declarative UI framework (primary)
- **UIKit**: Legacy UI components where needed
- **Combine**: Reactive programming framework
- **Core Data**: Local persistence and data management
- **AVFoundation**: Audio playback and session management
- **MediaPlayer**: Lock screen and control center integration

## iOS Frameworks
- **AVAudioSession**: Background audio configuration
- **FileManager**: File operations and security-scoped resources  
- **Foundation**: Core system services
- **CoreGraphics**: UI drawing and animations
- **UserNotifications**: Background notifications (planned)

## Development Tools
- **Xcode 16.4+**: IDE and project management
- **iOS 17.0+**: Minimum deployment target
- **Swift Package Manager**: Dependency management (if needed)
- **Git**: Version control

## Architecture Patterns
- **MVVM**: Model-View-ViewModel pattern with SwiftUI
- **ObservableObject**: State management with @Published properties
- **Environment**: Dependency injection for shared services
- **Coordinator Pattern**: Navigation management (implemented in Phase 3)

## Data Management
- **Core Data Stack**: Centralized persistence management
- **Background Context**: For import operations
- **Security-Scoped Resources**: File access management
- **Local File Storage**: App Documents directory