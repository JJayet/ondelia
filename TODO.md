# TODO — audit of 4 September 2026

Source: full read of the app, widget and test targets on `refactor/audio-engine-swift6`.

Verification performed after the pass below:

- `xcodebuild build` (app + widget extension): passed, 0 errors, 0 warnings.
- `xcodebuild build-for-testing` (app, unit and UI test targets): passed, 0 errors, 0 warnings.
- Unit suite `AudiobookReaderTests`: 105 tests in 20 suites, all passed.
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
- [ ] **CarPlay.** Requires an entitlement request to Apple before any code is worth writing.
- [ ] **Stale planning docs** `AudiobookReaderTests/PHASE_2_IMPLEMENTATION_SUMMARY.md`,
      `PHASE_3_IMPLEMENTATION_SUMMARY.md` and `README.md` describe infrastructure that does not
      exist (CarPlay, Watch, `PersistenceController`). Not deleted here because they were not in
      the audit; they should be.

## Needs a device to verify

- [ ] **Widget / Control Center from a cold start.** The intents now perform the work in the app
      process (`PlaybackCommands.perform`) instead of posting a Darwin notification that expires
      unheard; the extension's copy of the intent only compiles, guarded by `WIDGET_EXTENSION`.
      This cannot be exercised in the simulator — confirm on a device with the app force-quit.
- [ ] **Lock screen previous/next chapter** (`nextTrackCommand` / `previousTrackCommand`) and the
      re-applied skip interval: both are `MPRemoteCommandCenter` behaviour, so they need the real
      lock screen.
- [ ] **"Play &lt;book&gt;" App Shortcut phrase.** Spotlight indexing itself is verified working.
