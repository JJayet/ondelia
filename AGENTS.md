# Repository Guidelines

## Project Structure & Module Organization

- App entry: `AudiobookReader/App` (`AudiobookReaderApp.swift`, `MainTabView.swift`).
- Core logic: `AudiobookReader/Core`
  - Managers, Services, Models, SwiftData models. Shared singletons (`GlobalAudioManager`,
    `AudiobookManager`, `ThemeManager`) are read directly by the views that need them.
- Features: `AudiobookReader/Features/*` (e.g., `Player`, `Library`, `Settings`). Views end with `View`.
- Shared UI/utilities: `AudiobookReader/Shared` (e.g., `AccessibilityIdentifiers.swift`).
- Assets & config: `AudiobookReader/Resources` (colors, `Info.plist`, entitlements, `Localizable.xcstrings` String Catalog).
- Tests: `AudiobookReaderTests` (unit/integration) and `AudiobookReaderUITests` (UI).

## Build, Test, and Development Commands

- Build clean: `xcodebuild clean -project AudiobookReader.xcodeproj -scheme AudiobookReader -destination 'platform=iOS Simulator,name=iPhone 17'`
- Build for testing: `xcodebuild build-for-testing -project AudiobookReader.xcodeproj -scheme AudiobookReader -destination 'platform=iOS Simulator,name=iPhone 17'`
- Unit tests only: `xcodebuild test-without-building -project AudiobookReader.xcodeproj -scheme AudiobookReader -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AudiobookReaderTests`
- All tests (when UI tests compile): `xcodebuild test -project AudiobookReader.xcodeproj -scheme AudiobookReader -destination 'platform=iOS Simulator,name=iPhone 17'`
- Open in Xcode: `open AudiobookReader.xcodeproj` and run the `AudiobookReader` scheme.

## Coding Style & Naming Conventions

- Swift 6 language mode, iOS 26 minimum, 4‑space indentation, max ~120 cols; avoid force‑unwraps; prefer `guard` early exits.
- Types: PascalCase; methods/properties/locals: lowerCamelCase; constants allowed in upperCamelCase.
- Files named after primary type; SwiftUI views end with `View` (e.g., `PlayerView.swift`).
- Place code by layer: Managers→`Core/Managers`, Services→`Core/Services`, Features→`Features/<Feature>`.
- Accessibility IDs centralized in `Shared/AccessibilityIdentifiers.swift`.

## Testing Guidelines

- Framework: Swift Testing (`@Test` / `#expect`) for unit tests in `AudiobookReaderTests`; XCTest for UI tests in `AudiobookReaderUITests`. File names end with `Tests.swift` and mirror source paths.
- Prioritize coverage of Core and Player.
- UI tests: live under `AudiobookReaderUITests`. Prefer `AccessibilityIdentifiers` for queries.
- Run focused tests with `-only-testing:` (see commands above).

## Commit & Pull Request Guidelines

- Commits: prefer Conventional Commits.
  - Examples: `feat(player): add sleep timer`, `fix(core): handle empty CUE file`.
- PRs include: concise description, linked issues, simulator screenshots (iPhone 17), test plan (commands run), and notes on localization/entitlements changes.

## Security & Configuration Tips

- Do not commit secrets. Configure API keys outside source; never hardcode (see `GoogleImageSearchService`).
- Use HTTPS endpoints; follow CI checks in `.github/workflows/ci.yml`.
- Add new strings to `Localizable.xcstrings` and fill in French; avoid user data in logs.
