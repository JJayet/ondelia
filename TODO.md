# TODO — audit of 4 September 2026

Source: full read of the app, widget and test targets on `refactor/audio-engine-swift6`.

Verification performed after the pass below:

- `xcodebuild build` (app + widget extension): passed, 0 errors, 0 warnings.
- `xcodebuild build-for-testing` (app, unit and UI test targets): passed, 0 errors, 0 warnings.
- Unit suite `OndeliaTests`: 105 tests in 20 suites, all passed.
- UI suite: still not run (known broken, being consolidated into `AudiobookUITestCase.swift`).

Sections 1, 2, 3 and 4 are done except for the items listed under **Deliberately not done**.

---

## Deliberately not done

- [ ] **Migrate `NSLocalizedString` (≈270 uses) to `Text("key")` / `String(localized:)`.** Low
      priority, high noise, and the String Catalog already picks both spellings up. Worth doing
      file by file when those files are touched for another reason.
- [ ] **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on the app target.** Listed as optional in
      the original audit. The widget target already has it. Turning it on for the app means
      auditing every static service for `nonisolated`, and import work silently hopping to the
      main actor is the failure mode if that audit is wrong.
- [ ] **Import state machine → actor with an `AsyncStream` queue.** Seven flags still describe
      one running import. It works today; the original audit said refactor when next touched,
      and this pass did not need to touch it.
- [X] **CarPlay.** Scene, templates and entitlement are in (`Core/Services/CarPlay`). Dashboard
      interaction still untested on a real head unit.

## Open after the 5 September 2026 audit

- [X] **Rotate the Google Custom Search API key.** `Config/Secrets.xcconfig` was tracked until
      `74bf956`; commit `c11cf6b` still contains the key. Create a new key in Google Cloud Console,
      restrict it to bundle `io.jayet.Isora`, revoke the old one.
- [ ] **UI suite flake in CI.** One `xctrunner` clone failed to launch ("Application failed preflight
      checks", Busy) and the run was marked failed although 50/52 cases passed. Split the UI suite
      into its own CI job or add `-retry-tests-on-failure`.
- [ ] **19 functions over 50 lines**, all in the import pipeline (`copyFolderToDocuments`,
      `extractMetadata`, `makeFolderAudiobook`, `mergeAudiobooks`, `importAudiobook`, `parseCUEFile`…).
      No correctness issue; split when next touched.

## Needs a device to verify

- [X] **Widget / Control Center from a cold start.** The intents now perform the work in the app
      process (`PlaybackCommands.perform`) instead of posting a Darwin notification that expires
      unheard; the extension's copy of the intent only compiles, guarded by `WIDGET_EXTENSION`.
      This cannot be exercised in the simulator — confirm on a device with the app force-quit.
- [X] **Lock screen previous/next chapter** (`nextTrackCommand` / `previousTrackCommand`) and the
      re-applied skip interval: both are `MPRemoteCommandCenter` behaviour, so they need the real
      lock screen.
- [X] **"Play &lt;book&gt;" App Shortcut phrase.** Spotlight indexing itself is verified working.

## Open findings from the 12 September 2026 solution audit

Source-grounded, none reproduced on a device. Full write-up lived in `SOLUTION_AUDIT.md` and
`AUDIO_AUDIT.md`, both removed on 21 September 2026; the useful part is below.

Data protection first:

- [ ] **S01 P1: restore replaces the SQLite file while the container is open**
      (`DatabaseBackupService.swift:81`, `BackupRestoreView.swift:87`). Stage the restore and apply it
      before the container is created on next launch, keep the old store until the new one opens.
- [ ] **S02 P1: "Delete other files" deletes from a stale orphan report** (`StorageView.swift`).
      Re-fetch ownership right before deleting; exclude import staging.
- [ ] **S03 P2: backup validation uses an ad hoc five-model schema**, not `IsoraSchema` with its
      migration plan. `CollectionModel` and `ListeningSessionModel` are missing.
- [ ] **S04 P2: `VACUUM INTO` backup omits `.externalStorage` cover blobs.** Package the support
      directory or export covers explicitly.

Watch delivery:

- [ ] **S05 P2: `.exporting` / `.sending` queue rows survive a relaunch and are never picked up
      again** (`WatchTransferQueue.swift`). Requeue on activation, reconcile with
      `outstandingFileTransfers`.
- [ ] **S06 P2: chapter export has no `expirationHandler`** and the reader/writer pump ignores
      cancellation (`WatchSyncService+Transfers.swift:60`, `WatchAudioExporter.swift:143`).
- [ ] **S07 P2: a Watch bookmark gets a new UUID on the phone** (`WatchSyncService+Progress.swift:89`
      calls `createBookmark`). Upsert with the received id and date.
- [ ] **S08 P2: cover digest is marked sent on submission, not on delivery** (`watchSentCovers`).

Async and integrations:

- [ ] **S09 P2: `SpeechTranscriptionManager.transcribe` can start two jobs after the await.**
      Generation counter, check ownership after suspension.
- [ ] **S10 P2: finished Hardcover books bypass throttling and rewrite `finishedAt` to today on
      every tick** (`HardcoverService+Progress.swift:74`).
- [ ] **S11 P2: no `mediaServicesWereResetNotification` observer**; `hasActivatedAudioSession`
      stays set after a media-server reset. Invalidate, rebuild audio objects, wait for user action.
- [ ] **S12 P3: image search query uses `.urlQueryAllowed`**, so `War & Peace` splits into two
      parameters. Use `URLComponents` + `URLQueryItem`.

Audio, Dolby Atmos (from the same date):

- [ ] Comments in `AudiobookPlayer.moveQueue` and `configureSpatialAudio` overstate what
      `.monoStereoAndMultichannel` and `setSupportsMultichannelContent` do. Correct them; decide
      whether spatialising plain narration is wanted.
- [ ] No way to tell Atmos rendering from stereo fallback. Developer-only diagnostics (selected
      track codec, channel layout, route, `isSpatialAudioEnabled`) before any Atmos badge.
- [ ] Device matrix untested: Atmos reference file at each speed, AirPods modes, AirPlay, CarPlay,
      media-services reset, transcription during playback. Watch downloads are mono AAC 64 kbps by
      design; say "optimised audio", not Atmos.

## Adaptive layout (Apple tech talk "Bring your app to iPhone Duo")

Decision 21 September 2026: iPhone stays portrait-only. The Duo inner display ignores supported
orientations and reports regular/regular size classes. Use size classes together with available
container dimensions and reserved regions, never device idiom or interface orientation, for layout.
Portrait-only outer-display support remains a product choice; it excludes the landscape/tent experience.

- [X] Library grid: `.adaptive(minimum: 300 / gridColumns)`, the user preference sets density at
      phone width, wider windows get more columns.
- [X] Player: title beside the control column when `horizontalSizeClass == .regular`.
- [X] Settings, Statistics, Book detail, Collection detail: one column capped at 640 pt, centred.
- [X] Onboarding already adapts (`ViewThatFits`, 620 pt cap, compact header).
- [X] `TabView` already uses `.sidebarAdaptable`. No `UIScreen.main` in the app.
- [X] Continue Reading strip: a nested horizontal `ScrollView` spreads into the side safe areas,
      so on Duo closed the cards slid under the vertical toolbar and the "+" button. `.clipped()`
      on the strip fixes it (`ContinueReadingSection.swift`). Watch for the same in any other
      horizontal strip.
- [X] Duo closed pose checked on the simulator (22 September 2026): list, grid (2 columns), strip,
      vertical tab bar. Unit suite green on iPhone 17, builds green on iPhone 17 and iPhone Duo.
- [ ] Duo open pose: list checked, grid and player side-by-side not yet. Unfold in Device Hub,
      open a book. Then Split View on both sides: asymmetric safe areas, vertical bars on the left.
- [ ] `--seed-showcase` without `--reset-state` seeds again on every launch and duplicates the
      library. Harmless for the suites (they always reset), annoying for manual runs.
- [ ] **P2: make the custom player fold-aware** (`PlayerView+Layout.swift`). The fixed 40 pt
      two-column gap and centred chapter button do not account for the fold. Evaluate an
      `ArrangementView` or reserved-region handling, with an availability fallback for iOS 26.
      Keep controls within usable regions in book and tabletop poses; preserve access to all actions.
- [ ] **P2: add a player content-fit fallback** (`PlayerView+Layout.swift`). Regular horizontal
      size class alone does not guarantee that two columns fit: the inner display is regular/regular
      in both tall and wide layouts. Use available width/height and provide stacking or scrolling
      when needed. Check tips, queue content, long labels, and all playback controls together.
- [ ] **P2: adapt library toolbar actions for vertical presentation** (`LibraryView+Selection.swift`).
      Select, Cancel, and the selection-count menu currently have text-only labels. Add appropriate
      icons and semantic placements; verify entry to selection mode, cancellation, and bulk actions
      remain reachable in vertical bars and overflow menus.
- [ ] **P3: reconcile the grid preference with its label** (`LibraryView+Content.swift`,
      `SettingsView+Sections.swift`). The adaptive grid interprets the selected number as density,
      while Settings promises "Books per row". Preserve the exact count or rename/localize the
      preference to describe density; verify narrow and wide windows.
- [ ] **Restore build validation.** Xcode 27.1 is already installed (verified 22 September 2026).
      The review build failed on missing simulator SDK headers/overlay files and compiler-module
      errors. Resolve the toolchain issue and rerun a clean build before claiming build readiness;
      this failure did not establish a regression in the layout changes.
- [ ] **Run the Duo pose matrix:** outer display, fully open inner display in tall/wide layouts,
      partially folded book/tabletop poses, transitions between displays, and Split View on both
      sides. Check asymmetric safe areas, vertical bars on either side, and active camera occlusion.
      Include player, library, settings, secondary screens, sheets, menus, and popovers.
      Existing onboarding rotation tests do not unfold Duo and are not evidence for this matrix.
- [ ] Add focused UI regression checks for unreachable controls, clipping, and layout transitions;
      record actual display/window configurations and keep manual pose validation separate.
- [ ] Try the App Resizability skill from Xcode 27.1 on the project.
- [ ] Long French labels, large Dynamic Type and VoiceOver on the wide layouts.

Review basis (22 September 2026): [Apple's Duo preparation guidance](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo)
and supplied transcripts for tech talks 111461 and 111463. Checked items above describe implemented
resizing improvements, not completed Duo validation. A centred scrollable Settings column is valid;
a sidebar is optional. Source findings have not yet been reproduced across the full pose matrix.

## Dropped

- Volume boost: `AVQueuePlayer` has no gain stage, would need an `MTAudioProcessingTap` or an
  `AVAudioEngine` swap. Wait for a request.
- Audiobookshelf / Jellyfin: wait for server owners to show up as users.
- iOS 18 support: `SpeechAnalyzer` and glass effects are iOS 26 only.
