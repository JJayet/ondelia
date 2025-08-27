# AudiobookReader - Code Style & Conventions

## File Naming Conventions
- **Swift Files**: PascalCase (e.g., `AudiobookManager.swift`, `ThemeManager.swift`)
- **SwiftUI Views**: Descriptive names ending in "View" (e.g., `EnhancedLibraryView.swift`)
- **Services/Managers**: Descriptive names ending in "Manager" or "Engine" (e.g., `AudioEngine.swift`)
- **Data Models**: Entity names without suffixes (e.g., `Audiobook.swift`)

## Swift Coding Standards
- **Property Naming**: camelCase for all properties
- **Method Naming**: camelCase with descriptive verb-first names
- **Class Names**: PascalCase
- **Constants**: camelCase or UPPER_SNAKE_CASE for global constants
- **Private Members**: Use `private` or `fileprivate` appropriately

## SwiftUI Patterns
- **State Management**: Use `@State`, `@StateObject`, `@ObservedObject` appropriately
- **Environment**: Inject dependencies via `.environment()` modifier
- **ViewModels**: ObservableObject classes with `@Published` properties
- **View Structure**: Break complex views into smaller, reusable components

## Code Organization
- **Extensions**: Group related functionality in separate extensions
- **MARK Comments**: Use `// MARK: -` to organize code sections
- **Documentation**: Use Swift documentation comments (`///`) for public APIs
- **Imports**: Group and order imports (Foundation, UIKit, SwiftUI, then third-party)

## Architecture Patterns
- **MVVM**: Separate business logic from view logic
- **Single Responsibility**: Each class/struct has one clear purpose
- **Dependency Injection**: Use environment for shared services
- **Error Handling**: Use Result types and proper error propagation

## Current File Structure (Flat - Needs Reorganization)
All files currently in `AudiobookReader/` directory:
- App entry points
- Views (various feature screens)
- Services and managers
- Data models and Core Data stack
- Resources and configuration