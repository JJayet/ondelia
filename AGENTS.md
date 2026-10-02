# Repository Guidelines

## Project Structure & Module Organization

- App entry: `Ondelia/App` (`IsoraApp.swift`, `MainTabView.swift`).
- Core logic: `Ondelia/Core`
  - Managers, Services, Models, SwiftData models. Shared singletons (`GlobalAudioManager`,
    `AudiobookManager`, `ThemeManager`) are read directly by the views that need them.
- Features: `Ondelia/Features/*` (e.g., `Player`, `Library`, `Settings`). Views end with `View`.
- Shared UI/utilities: `Ondelia/Shared` (e.g., `AccessibilityIdentifiers.swift`).
- Assets & config: `Ondelia/Resources` (colors, `Info.plist`, entitlements, `Localizable.xcstrings` String Catalog).
- Tests: `OndeliaTests` (unit/integration) and `OndeliaUITests` (UI).

- The Xcode project, schemes, targets, and products use Ondelia. Internal Swift module names
  (including `Isora` for test imports), bundle IDs, and storage IDs remain stable for compatibility.

## Build, Test, and Development Commands

- Build clean: `xcodebuild clean -project Ondelia.xcodeproj -scheme Ondelia -destination 'platform=iOS Simulator,name=iPhone 17'`
- Build for testing: `xcodebuild build-for-testing -project Ondelia.xcodeproj -scheme Ondelia -destination 'platform=iOS Simulator,name=iPhone 17'`
- Unit tests only: `xcodebuild test-without-building -project Ondelia.xcodeproj -scheme Ondelia -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OndeliaTests`
- All tests (when UI tests compile): `xcodebuild test -project Ondelia.xcodeproj -scheme Ondelia -destination 'platform=iOS Simulator,name=iPhone 17'`
- Open in Xcode: `open Ondelia.xcodeproj` and run the `Ondelia` scheme.

## Coding Style & Naming Conventions

- Swift 6 language mode, iOS 26 minimum, 4‑space indentation, max ~120 cols; avoid force‑unwraps; prefer `guard` early exits.
- Types: PascalCase; methods/properties/locals: lowerCamelCase; constants allowed in upperCamelCase.
- Files named after primary type; SwiftUI views end with `View` (e.g., `PlayerView.swift`).
- Place code by layer: Managers→`Core/Managers`, Services→`Core/Services`, Features→`Features/<Feature>`.
- Accessibility IDs centralized in `Shared/AccessibilityIdentifiers.swift`.

## Testing Guidelines

- Framework: Swift Testing (`@Test` / `#expect`) for unit tests in `OndeliaTests`; XCTest for UI tests in `OndeliaUITests`. File names end with `Tests.swift` and mirror source paths.
- Prioritize coverage of Core and Player.
- UI tests: live under `OndeliaUITests`. Prefer `AccessibilityIdentifiers` for queries.
- Run focused tests with `-only-testing:` (see commands above).

## Commit & Pull Request Guidelines

- Commits: prefer Conventional Commits.
  - Examples: `feat(player): add sleep timer`, `fix(core): handle empty CUE file`.
- PRs include: concise description, linked issues, simulator screenshots (iPhone 17), test plan (commands run), and notes on localization/entitlements changes.

## Versioning & Changelog

- Every change to `MARKETING_VERSION` (App Store version) adds a section to `CHANGELOG.md` in the
  same commit: user-facing changes since the previous version, in English and French, ready for
  App Store Connect's "What's New". Use the app's UI terms from `Localizable.xcstrings`.
- Build-number-only bumps (`CURRENT_PROJECT_VERSION`) update the existing section's heading.

## Security & Configuration Tips

- Do not commit secrets. Configure API keys outside source; never hardcode (see `GoogleImageSearchService`).
- Use HTTPS endpoints; follow CI checks in `.github/workflows/ci.yml`.
- Add new strings to `Localizable.xcstrings` and fill in French; avoid user data in logs.

## Agent skills

### Issue tracker

Issues live in GitHub Issues on `JJayet/ondelia` (via `gh` CLI). See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` + `docs/adr/` at repo root. See `docs/agents/domain.md`.
