# Apple Watch companion — implementation plan

Decisions taken with the author on 6 September 2026:

- **Mode:** remote control of the iPhone *and* offline playback of chapters stored on the watch.
- **Chapters reach the watch one at a time.** Folder books already have one file per chapter;
  single-file books (m4b/mp3 with markers, CUE) are cut on the iPhone.
- **Everything sent to the watch is transcoded to AAC 64 kbps mono** (~25 MB per hour).
- **Progress sync:** last write wins by timestamp, plus "starting playback on one side pauses the
  other side when reachable". Handoff (watch → iPhone) as a bonus on top.
- **Minimums:** watchOS 26, Swift 6 language mode, French strings on day one, SwiftData models
  shared with the watch target.
- The watchOS target is created in Xcode by the author (*Watch App for Existing iOS App*, target
  `Isora`), product `IsoraWatch`, bundle `io.jayet.Isora.watchkitapp`.

## Hard constraints (cannot be designed away)

| Constraint | Consequence in the design |
|---|---|
| watchOS plays long-form audio to Bluetooth headphones only. | The player screen shows "Connecte des AirPods" when `AVAudioSession` reports no Bluetooth route. `activate(options:)` shows the system route picker. |
| The watch cannot read iPhone files or the iPhone app group. | Every byte crosses `WatchConnectivity`. |
| `WCSession.transferFile` runs over Bluetooth at a few hundred KB/s (much faster when both are on the same Wi‑Fi). | A 51‑minute chapter at 64 kbps ≈ 25 MB ≈ 1–3 min. The design's progress bar (4c) is mandatory, not decorative. |
| A `sendMessage` from the watch wakes the iOS app in the background, but background time is short (tens of seconds). | Chapter export is queued and persisted; the watch asks for chapter *N+2* when chapter *N* starts so the phone has time. If the export outlives the background window it resumes on next foreground. |
| `updateApplicationContext` is coalesced (only the latest dictionary is delivered) and limited to ~256 KB. | Library state goes in `applicationContext`; one-shot events (progress writes, bookmark created, chapter request) go through `transferUserInfo`, which is queued and guaranteed. |
| Handoff exists only from watch to iPhone and requires a user tap. | Handoff is a convenience banner. Real continuity comes from progress sync. |
| WidgetKit accessory widgets on watchOS: tap opens the app. | "Reprendre" in the complication deep-links `isora://resume`, the app starts playback on launch. |

## Architecture

```
Isora (iOS)                              IsoraWatch (watchOS)
────────────                             ────────────────────
GlobalAudioManager ──┐                   WatchAudioManager (thin: owns one AudiobookPlayer)
AudiobookManager     │                   WatchLibraryStore (SwiftData, IsoraSchemaV1, watch-local)
                     ▼
WatchSyncService  ◄──── WCSession ────►  PhoneSyncService
   │  applicationContext: LibrarySnapshot (≤ 3 books + chapters + positions)
   │  transferUserInfo:   SyncEvent (progress, bookmark, chapterRequest, deleteChapter, command)
   │  transferFile:       cover JPEG 256 px, chapter .m4a
   │  sendMessage:        RemoteCommand (toggle/skip/play book) + pauseOtherSide
   ▼
WatchAudioExporter (AVAssetReader → AVAssetWriter, AAC 64 kbps mono, one chapter at a time,
                    persisted queue in UserDefaults)
```

### Files shared between both targets (target membership only, no code change unless noted)

- `Core/Models/SwiftData/AudiobookModel*.swift`, `ChapterModel`, `BookmarkModel`,
  `ChapterTranscriptionModel`, `HardcoverLink`, `IsoraSchema`.
  Schema change: add `var positionUpdatedAt: Date?` to `AudiobookModel` (optional, same
  pattern as `playbackSpeed`, so the store keeps opening). Needed for last-write-wins.
- `Core/Services/AudiobookPlayer.swift`, `AudiobookPlayer+Tracks.swift`, `SafeImportPath.swift`,
  `Log.swift`. The player already handles a folder whose manifest lists chapters that are not
  on disk: the gap stays on the timeline and only the audio is dropped. That is exactly the
  watch's partial-book case. One addition: an `onTrackEnded(index:)` callback so the watch can
  pause and show "Demander le ch. N" instead of jumping to the next present chapter.
- `Shared/NowPlayingSharedStore.swift` (already `nonisolated`, imports only WidgetKit and
  Foundation) — feeds the watch complications through the watch-local app group.
- `Shared/LiquidGlass.swift` cover tint sampler for the crown/glass tint in 3a.
- `Resources/Localizable.xcstrings` — one catalog, add the watch strings with French.
- `SwiftDataController` is **not** shared (it imports SwiftUI and `UITestBootstrap`). The watch
  gets `WatchLibraryStore`, ~40 lines: `ModelContainer(for: IsoraSchemaV1, migrationPlan:)`
  in the watch's Application Support.

### New files

**Shared (both targets), `Isora/Shared/WatchSync/`**

- `SyncModels.swift` — `Codable` value types: `LibrarySnapshot`, `BookSummary`, `ChapterSummary`,
  `SyncEvent` (enum), `RemoteCommand` (enum), `FileTransferKind` (cover / chapter) with the
  metadata keys used on `transferFile`. Pure Foundation, unit-tested for round-trip.

**iOS, `Isora/Core/Services/Watch/`**

- `WatchSyncService.swift` — `WCSessionDelegate`. Builds `LibrarySnapshot` from
  `AudiobookManager.audiobooks` (three books: content on the watch first, then most recent
  `lastPlayed`, unfinished), pushes it on every relevant change (progress persist, bookmark,
  library change, playback state). Receives events and commands, forwards to
  `GlobalAudioManager` / `AudiobookManager`.
- `WatchSyncService+Progress.swift` — last-write-wins merge, `pauseOtherSide` handling.
- `WatchAudioExporter.swift` — one chapter → `.m4a` in `tmp`, then `transferFile`. Reader on
  the chapter's `CMTimeRange` (single-file books) or on the chapter file (folder books), writer
  with `AVFormatIDKey: kAudioFormatMPEG4AAC, AVEncoderBitRateKey: 64_000, channels: 1`.
  Wrapped in `beginBackgroundTask`. Serial queue, persisted, retried on launch.
- `WatchTransferQueue.swift` — the persisted list of `(bookID, chapterNumber)` to export/send,
  plus the rolling window rule: when the watch reports it is at chapter *N*, keep *N…N+2* on it.

**iOS UI**

- Book detail: one row "Envoyer sur l'Apple Watch" (only when
  `WCSession.isPaired && isWatchAppInstalled`). Tapping queues the current chapter and the two
  after it. Status text under it mirrors the watch state (envoi 62 %, 3 chapitres sur la montre).
- `Features/Settings`: "Apple Watch" section: what is on the watch, "Vider".

**watchOS, `IsoraWatch/`**

- `IsoraWatchApp.swift` — `@main`, deep-link handling (`isora://resume`), Handoff activity.
- `PhoneSyncService.swift` — `WCSessionDelegate`. Applies `LibrarySnapshot` into the local
  SwiftData store (upsert by `id`, chapters replaced, positions merged by timestamp). Handles
  `didReceive file:` — **moves the file synchronously** (WC deletes it after the callback) into
  `Documents/Audiobooks/<bookID>/` and rewrites `audiobook_manifest.json` with *all* chapters of
  the book (present or not), so `AudiobookPlayer+Tracks` builds the full timeline.
- `WatchAudioManager.swift` — owns one `AudiobookPlayer`, the sleep timer, speed, progress
  persistence (every 30 s and on pause), `AVAudioSession` `.longFormAudio` activation, Now Playing
  info. Sends `progress` events and `pauseOtherSide` on play. On `onTrackEnded` with the next
  chapter missing: pause, show request.
- `WatchTransferState.swift` — `@Observable` per-chapter state (`ready`, `receiving(fraction)`,
  `queued`, `missing`). Only the *sender* sees `WCSessionFileTransfer.progress`, so the phone
  forwards `fractionCompleted` through `sendMessage` when reachable; otherwise the watch shows
  "en attente" until the file lands.
- Views (SwiftUI, watchOS 26 components):
  - `EnCoursView` (3b): list of ≤ 3 books, status line, trailing play or download button,
    footer "Chapitres". Root of the `NavigationStack`.
  - `WatchPlayerView` (3a): cover + title + chapter, progress with elapsed/remaining, ±15 s,
    play/pause, chips speed / sleep timer / bookmark. `.digitalCrownRotation` with 15 s per
    detent; glass tint from the cover via `LiquidGlass`.
  - `NothingOnWatchView` (4b): empty state, "Demander le ch. N" when the snapshot has a book in
    progress on the phone.
  - `OnWatchStorageView` (4c): chapter rows with state, play, swipe to delete, footer
    "160 Mo utilisés · Vider".
  - `WatchChaptersView`, `SleepTimerPickerView` (off / 10 / 15 / 25 / 45 min / fin du chapitre),
    `SpeedPickerView` (0.8 … 2.0).
- `IsoraWatchWidget/` (WidgetKit extension on the watch): `accessoryCircular` (68 % du chapitre),
  `accessoryRectangular` (title · ch. 14 · 17 h 09), `accessoryCorner` (Reprendre). Reads
  `NowPlayingSharedStore` from the watch app group. Tap → `isora://resume`.

### Remote-control path ("sur l'iPhone")

When the phone is playing, the snapshot carries `nowPlaying` (book id, position, rate, isPlaying).
The watch shows the same player screen with a small "sur l'iPhone" label; transport buttons send
`RemoteCommand` via `sendMessage` (falls back to `transferUserInfo` when unreachable). The phone
answers with a fresh snapshot. Tapping a book that is on the phone but not on the watch = play on
the phone, plus the download button next to it.

### Progress rules

1. Both sides store `currentPosition` + `positionUpdatedAt`.
2. Writer sends `progress(bookID, position, at)` every 30 s while playing and on pause/stop.
3. Receiver applies it only if `at > local positionUpdatedAt`.
4. `play` on either side sends `pauseOtherSide` first when `isReachable`; the receiver pauses and
   persists, which produces a progress event, which lands before the sender's first tick.
5. Handoff: `WatchPlayerView` publishes `NSUserActivity("io.jayet.Isora.listening")` with book id
   and position. iPhone `onContinueUserActivity` loads the book and seeks. Bonus only.

### Storage rules on the watch

- At most three books have content. Sending a fourth prompts on the phone to pick one to clear.
- A chapter is evicted automatically once `currentPosition` is past its end and the position was
  written on the watch (the listener finished it there). "Vider" and swipe-delete are manual.
- Sizes shown are real file sizes; "160 Mo utilisés" sums the folder.

## Phases

| # | Deliverable | Verifiable by |
|---|---|---|
| 1 | Target created (author, Xcode). Shared files added to watch membership. `WatchLibraryStore`. App shows `NothingOnWatchView`. | Watch simulator runs, 0 warnings. |
| 2 | `SyncModels` + `WatchSyncService` + `PhoneSyncService`: snapshot → `EnCoursView` with covers. Remote transport of the iPhone from the watch. | Paired simulators: play/pause on the watch drives the phone. Unit tests: codec round-trip, three-book selection. |
| 3 | `WatchAudioExporter` + `WatchTransferQueue` + file receive + manifest + `WatchAudioManager` + `WatchPlayerView` + `OnWatchStorageView`. "Envoyer sur l'Apple Watch" on the phone. Missing-chapter request. | A chapter of a single-file book plays on the watch with the phone in airplane mode. Unit test: export of a 3 s generated asset yields a playable mono AAC. |
| 4 | Progress LWW, `pauseOtherSide`, bookmarks from the watch, speed, sleep timer. | Unit test on the merge rule. Manual: pause on the watch, resume on the phone at the same spot. |
| 5 | Complications + `isora://resume` + Handoff. | Complication on the face resumes playback. |
| 6 | French strings, cover tint, haptics, storage eviction, Settings section. | String catalog has no missing French rows. |

Phases 2 and 3 are the bulk. Phase 5 is independent of 3 and 4 and can be pulled earlier.

## Risks and what verifies them

- **Background export time on the phone.** Only a device shows the real budget. Mitigation is
  already in the design (persisted queue, request two chapters ahead). If it proves too short,
  fallback is `BGProcessingTask` scheduled by the watch request.
- **Transfer throughput.** Measure on a device with Wi‑Fi off; if a 25 MB chapter takes more than
  ~5 min, lower to 48 kbps or split chapters longer than 60 min into two files.
- **SwiftData writes from `WCSessionDelegate` callbacks.** Delegate methods arrive off the main
  actor; every store write hops to `@MainActor`. Same pattern the widget intents use.
- **`AVQueuePlayer` on watchOS with gaps.** The existing gap handling was written for iOS; the
  `onTrackEnded` hook must be tested with a missing middle chapter on the watch simulator.

## Out of scope for v1

Transcriptions on the watch, Hardcover on the watch, importing on the watch, cover editing,
Ultra 49 mm layout variant (design note says "à essayer ensuite"), notifications.
