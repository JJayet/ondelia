# Missing Features Compared with BookPlayer

Comparison date: 2026-09-07.

This backlog comes from inspecting the current local Isora and BookPlayer repositories. It describes implementation gaps, not a comparison of released App Store versions. Playback reliability, visual polish, accessibility, and performance have not been validated side by side. Priorities below are recommendations, not committed scope.

Effort is an estimate for one developer familiar with the codebase, derived from the Isora code each feature touches (see "Effort basis" per row). S = under a day, M = 1–3 days, L = 1–2 weeks, XL = multiple weeks or an external dependency.

## Recommended priorities (value per effort)

1. ~~**Separate skip intervals** (S)~~ Done 2026-09-08, Watch fix included.
2. ~~**Automatic sleep timer** (S)~~ Done 2026-09-08.
3. ~~**Undo last seek** (S–M)~~ Done 2026-09-08. "Back to 12:34" row in the player for 60 s after a jump of 10 s or more.
4. ~~**Storage usage view** (M)~~ Done 2026-09-08. Per-book sizes, orphan total, swipe to delete.
5. ~~**Bulk select, delete, and mark finished** (M)~~ Done 2026-09-08.
   ~~Custom collections~~ Done 2026-09-08: `CollectionModel` (ordered book ids, synced). Hardcover series are collections made automatically (Settings > Library toggle; off, the library offers each new series once). Hand-made collections via Select or a book's menu; a book can be in several and stays on the main shelf too. Series cards can hide the volumes you do not own. Ordering per collection: Manual (drag, or Move Up / Move Down), Series order, Title, Author, Date Added, Publication date (Hardcover `release_date`, fetched with the book details).
   Also added: Settings > Playback "Delete book when finished".
6. **CarPlay** (L, plus entitlement lead time). Request the entitlement now; build once granted.
7. ~~**Cloud position/bookmark sync via CloudKit** (L)~~ Done 2026-09-08. SwiftData + CloudKit private database, on by default, Settings > Data toggle.
   - Synced: books, positions, finished state, bookmarks, chapters, covers, transcripts, Hardcover links. Audio never syncs; a book without its file shows "Not on this device" and importing the same file or folder fills it in.
   - Before release: deploy the schema from the CloudKit Console development environment to production, and open Signing & Capabilities once so Xcode registers the `iCloud.io.jayet.isora` container.
   - Known gaps: the same book imported on two devices before they sync makes two rows (no automatic dedupe); restoring a database backup on a syncing device can resurrect deleted rows.
8. Everything else: wait for a concrete user request.

Dropped from the earlier order: recovery bookmarks moved from #1 to #3 in a much smaller form, and Audiobookshelf integration moved off the list until server owners show up as users.

## Missing features and areas to extend

| Feature | What BookPlayer provides | Isora today | Suggested scope | Effort | Effort basis |
| --- | --- | --- | --- | --- | --- |
| Separate skip intervals | Independently configurable backward and forward intervals, including chapter navigation options. | One shared `SkipInterval` in `ThemeManager`; watch hardcodes 15 s in `WatchAudioManager+Session.swift` and `WatchAudioManager.swift`. | Split the setting in two. Reuse the existing `SkipInterval` enum and settings picker. Push both values to the Watch through the existing sync snapshot. | **S** | Six call sites: `ThemeManager+Settings`, `SettingsView+Sections`, `PlayerView+Controls`, `GlobalAudioManager+Playback` defaults, `GlobalAudioManager+RemoteCommands`, watch. Widgets and App Intents already use the manager defaults. |
| Automatic sleep timer | Automatically starts a configured sleep timer when playback starts. | Manual sleep timer with fade-out and end-of-chapter support in `GlobalAudioManager+SleepTimer`. | One opt-in toggle plus "last used duration". In `resumePlayback`, start the timer when the toggle is on and no timer is running. | **S** | Timer logic exists. New code is one `@AppStorage` flag, one stored duration, one guard in `resumePlayback`. |
| Undo last seek (replaces "automatic recovery bookmarks") | Automatic bookmarks for playback, skips, and sleep-timer events, alongside manual bookmarks and export. | Manual bookmarks only. Smart rewind already covers pause/resume drift. | Remember the position before each seek or skip and show a temporary "Back to 12:34" chip in the player. Covers the accidental-scrub case without a history table. | **S–M** | One stored `TimeInterval` in `GlobalAudioManager.seek`, one chip in the player. A full BookPlayer-style history would add a `kind` field to `BookmarkModel`, write on every skip and sleep event, and filter the bookmarks list: **M**, for little extra value. |
| Storage usage view | File sizes, artwork-cache visibility, repair actions, and cloud offloading/download management. | Backup restoration and book deletion; no size information anywhere. | Show total and per-book size in Settings and `BookDetailView`. Skip offloading: there is no recoverable source without cloud or server support. | **M** | `FileManager` size walk per `resolvedFileURL`, one settings row, one detail row. `ZIPImporter` already has the size-walk pattern. |
| Bulk library management | Multi-selection, bulk move/delete/mark-finished operations, custom folders, and manual ordering. | Individual actions in `BookActionsMenu`. `AudiobookManager` already has `deleteAudiobook` and `markAsFinished`. | Phase 1: selection mode on the library grid with delete and mark-finished. Phase 2 (defer): user-defined collections and manual ordering. | **M** (phase 1) / **L** (phase 2) | The library is a `LazyVGrid`, not a `List`, so selection needs a custom `Set<UUID>` and edit-mode toolbar. Collections need a new `@Model`, a relationship on `AudiobookModel`, assignment UI, and rules for coexisting with automatic series grouping. |
| CarPlay | Dedicated library, recent books, and player integration, including cold-launch handling. | No CarPlay scene or entitlement. Now Playing and remote commands already exist. | Request the CarPlay audio entitlement first (Apple review, typically weeks). Then add a scene manifest, a `CPTemplateApplicationSceneDelegate`, a list template for recent/library, and reuse `MPNowPlayingInfoCenter`. | **L** + entitlement wait | Entitlements file has Siri and app groups only. No scene manifest in `Info.plist`, so the SwiftUI app needs one added. Lock-screen transport already works, which removes the hardest part. |
| Cloud position and bookmark sync | Library uploads/downloads, metadata and bookmark synchronization, queued operations, and remote files. | Phone–Watch sync via `WatchSyncService`. `positionUpdatedAt` already exists for last-writer-wins. | CloudKit via SwiftData for positions, bookmarks, and finished state only. Audio stays local and is matched per device by title/author or file hash. Do not sync audio files. | **L** | SwiftData CloudKit requires removing `@Attribute(.unique)` on `AudiobookModel.id`, making relationships optional, and defaulting every property. Matching books across devices and reconciling with Watch sync is the real work. Full library sync including audio: **XL**, months. |
| Audiobookshelf and Jellyfin integration | Server browsing and audiobook downloads. | File/folder/ZIP imports; no server connections. | Only if server owners are a target audience. Start with Audiobookshelf: login, browse, download to the existing import path, optionally push progress. | **L–XL** | API client, browse UI, download manager, credential storage, progress sync semantics. Nothing in the codebase to reuse beyond the import path. |
| Volume boost | A volume boost setting. | `AVQueuePlayer` with `volume` capped at 1. Sleep-timer fade uses the same property. | Drop unless requested. `AVQueuePlayer` has no gain stage. Options are an `MTAudioProcessingTap` per item or moving to `AVAudioEngine`. | **L** (tap) / **XL** (engine swap) | The player was recently consolidated onto one `AVQueuePlayer`. An engine swap reopens that work. |
| Additional playback preferences | More control/display options, including progress seeking, startup behavior, and configurable smart rewind. | Skip interval, book opening delay, chapter times, smart rewind, scrub scope. | Add one option at a time when a user asks. Each is a settings row plus one read. | **S** each | Settings pattern is established in `SettingsView+Sections`. |
| Older OS support | The inspected checkout targets iOS 18 and watchOS 10. | Isora targets iOS 26 and watchOS 26. | Keep iOS 26. | **XL** | Transcription uses `SpeechAnalyzer` (iOS 26 only) and 18 files use glass effects. Supporting iOS 18 means an `SFSpeechRecognizer` fallback and availability branches across the UI. By late 2026, iOS 26 adoption makes this a poor trade. |

## Features already present in Isora

Do not treat these as missing merely because BookPlayer also offers them:

- Local Apple Watch playback and phone–Watch synchronization.
- Widgets and playback shortcuts.
- Chapter navigation and manual bookmarks.
- Smart rewind.
- Per-book speed and a shared speed option.
- A play queue.
- Sleep timer, fade-out, and end-of-chapter timing.
- File, folder, and ZIP importing.
- Hardcover integration.

Presence in the implementation does not establish equivalent reliability or usability. These areas need focused runtime comparisons before making quality claims.

## Known defect found during this review

- ~~The Watch ignores the phone's skip interval.~~ Fixed 2026-09-08: the snapshot now carries both intervals.

## Isora strengths to preserve

- **Synchronized on-device transcription:** sentence highlighting and tap-to-seek. Availability depends on device/language support, and recognition accuracy still needs practical evaluation.
- **Transcript translation:** a comprehension and language-learning workflow that retains the original transcript.
- **Listening goals and statistics:** monthly goals, accumulated listening time, and streaks.
- **Hardcover listening progress:** Isora sends listening seconds against an audiobook edition, supporting percentage progress where an edition is available. BookPlayer's inspected tracking flow updates reading/read status.
- **Automatic local series grouping:** Hardcover metadata organizes local books into series. BookPlayer's custom folders and Audiobookshelf series browsing serve different workflows.

## Source references

Paths below are relative to the Isora repository root. BookPlayer references require its sibling checkout at `../BookPlayer`.

### BookPlayer

- [Library operations](../BookPlayer/BookPlayer/Library/ItemList/ItemListViewModel.swift)
- [Cloud synchronization](../BookPlayer/Shared/Services/Sync/SyncService.swift)
- [CarPlay](../BookPlayer/BookPlayer/Services/CarPlayManager.swift)
- [Automatic bookmarks](../BookPlayer/BookPlayer/Player/Views/Bookmarks/BookmarksViewModel.swift)
- [Bookmark presentation and export](../BookPlayer/BookPlayer/Player/Views/Bookmarks/BookmarksView.swift)
- [Playback preferences](../BookPlayer/BookPlayer/Settings/Sections/PlayerControls/SettingsPlayerControlsView.swift)
- [Separate skip intervals](../BookPlayer/BookPlayer/Settings/Sections/PlayerControls/SkipIntervalsSectionView.swift)
- [Storage management](../BookPlayer/BookPlayer/Settings/Storage/StorageView.swift)
- [Hardcover tracking](../BookPlayer/BookPlayer/Hardcover/Network/HardcoverService.swift)
- [Feature overview](../BookPlayer/README.md)

### Isora

- [Skip interval setting](Isora/Core/Managers/ThemeManager+Settings.swift)
- [Remote commands and Now Playing](Isora/Core/Managers/GlobalAudioManager+RemoteCommands.swift)
- [Playback and seek](Isora/Core/Managers/GlobalAudioManager+Playback.swift)
- [Sleep timer](Isora/Core/Managers/GlobalAudioManager+SleepTimer.swift)
- [Player engine](Isora/Core/Services/AudiobookPlayer.swift)
- [Data model](Isora/Core/Models/SwiftData/AudiobookModel.swift)
- [Bookmark model](Isora/Core/Models/SwiftData/BookmarkModel.swift)
- [Library and series grouping](Isora/Features/Library/LibraryView.swift)
- [Book actions](Isora/Features/Library/BookActionsMenu.swift)
- [Settings](Isora/Features/Settings/SettingsView+Sections.swift)
- [Entitlements](Isora/Resources/Isora.entitlements)
- [On-device transcription](Isora/Core/Services/SpeechTranscriptionManager.swift)
- [Synchronized transcript](Isora/Features/Player/TranscriptSyncView.swift)
- [Transcript translation workflow](Isora/Features/Player/TranscriptionView.swift)
- [Listening statistics](Isora/Core/Managers/ReadingStatistics.swift)
- [Hardcover progress](Isora/Core/Services/HardcoverService+Progress.swift)
- [Watch playback](IsoraWatch%20Watch%20App/Audio/WatchAudioManager.swift)
- [Watch remote commands](IsoraWatch%20Watch%20App/Audio/WatchAudioManager+Session.swift)
