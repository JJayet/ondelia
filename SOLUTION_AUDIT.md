# Ondelia — full solution audit

Date: 2026-09-12  
Baseline: `ca8e95a`, branch `feat/onboarding`  
Environment: Xcode 26.6 (17F113), iPhone 17 simulator

## Assessment

The solution builds and its iPhone unit/integration suite passes, but the recovery and cross-device paths need additional work before they can be considered dependable. The most urgent issues are replacing an open database during restore and deleting audio using an outdated orphan-file report. Watch transfer recovery and bookmark identity are the next priorities.

This review identifies **12 actionable findings: 2 P1, 9 P2, and 1 P3**. P1 means potential data loss requiring early correction; P2 means a reliability or correctness defect; P3 means a narrower functional issue. These are source-grounded findings, not claims that every failure was reproduced on a device.

No production code was changed. This report extends the earlier [audio audit](AUDIO_AUDIT.md), which remains the detailed reference for Dolby Atmos, output routes, speed changes, and Watch audio conversion.

## Scope and evidence

The scope is the Ondelia Xcode solution: iPhone app, shared models/services, Watch app, widgets, App Intents, CarPlay, import/storage, SwiftData/CloudKit, transcription, statistics, external integrations, and build configuration. The sibling website and BookPlayer repository are outside this solution audit.

Review depth is concentrated on data integrity, async lifecycle, cross-device delivery, large-library behavior, and externally visible failures. This is not a claim of exhaustive line-by-line or visual inspection of every view.

| Area | Inspected behavior | Outcome / remaining validation |
| --- | --- | --- |
| Startup and persistence | Container creation, migration schema, load/save error paths, backups | Startup avoids destructive automatic reset; restore and backup completeness have findings |
| Import and storage | Streaming copies, archive limits, path containment, re-import/relink, merge, orphan cleanup | Stronger archive/copy safeguards; stale deletion report remains unsafe |
| Playback and audio session | Session activation, progress, queue behavior, remote controls | Existing audio audit applies; reset recovery still missing |
| Transcription | iOS 26 SpeechAnalyzer lifecycle, window reader, locale selection, caching, view result guards | Windowed streaming is appropriate; manager replacement can interleave |
| Watch | Persistent transfer queue, export, file receipt, snapshots, progress and bookmarks | Several delivery/restart/idempotency defects |
| Widgets and App Intents | Shared state, playback commands, app startup coordination | Architecture inspected; extension interaction not exercised live |
| CarPlay | Scene startup, template lists, callbacks and thumbnail loading | Startup waits for store; actual dashboard interaction untested |
| Statistics | Listening log, progress timer, milestone evaluation and aggregations | Large-history CPU work merits profiling; earned milestones already skip recomputation |
| Integrations | Hardcover progress, credentials/API handling, image search, tip jar | Hardcover completion and search encoding findings; no live account actions |
| Configuration | Project/scheme, deployment targets, module identity, CI, entitlements and privacy manifests | Swift 6 / OS 26 configuration; shipping-signature and privacy validation remain release checks |

CodeGraph was attempted first as required by repository guidance. Its index still referenced pre-rename paths without usable source, so the review used the current files directly.

## Prioritized findings

### S01 — P1: Restore replaces a database while its container is still open

**Evidence:** `Ondelia/Core/Models/SwiftData/DatabaseBackupService.swift:81`, `Ondelia/Features/Settings/BackupRestoreView.swift:87`.

The settings action obtains the running container's store URL, deletes the database and its WAL/SHM files, and copies the selected backup into that path. The old container and model contexts remain alive. An alert asks the user to relaunch, but does not stop playback, saves, or CloudKit activity before the filesystem replacement. Copy failure also occurs after the live files have been deleted, with no rollback.

**Failure scenario:** restore while the app has an active store; a subsequent save still uses the old open connection, or the replacement copy fails. The next launch can encounter missing, inconsistent, or unexpected persisted data. SQLite explicitly warns against unlinking an open database because connections and journal names can become inconsistent. [SQLite corruption guidance](https://www.sqlite.org/howtocorrupt.html).

**Fix:** stage and validate a restore request, then apply it before creating any model container on the next startup. Use a rollback-capable replacement sequence and retain the previous complete store until the restored store opens successfully. Define how restored local state interacts with CloudKit before reconnecting sync.

**Acceptance:** on disposable libraries, inject copy/open failures at each step and prove the previous store remains recoverable. Test restore with pending playback progress and later CloudKit reconciliation. Do not test destructive recovery against the user's real library.

### S02 — P1: “Delete other files” trusts a stale ownership snapshot

**Evidence:** `Ondelia/Features/Settings/StorageView.swift:35`, `:62`, `:69`, `:115`.

The view builds a report asynchronously and retains its orphan URL list. The confirmation action deletes that stored list without refreshing ownership. Disabling the entry button while `manager.isImporting` is true does not revalidate the report or protect the final deletion action.

**Failure scenario:** open Storage while an import has copied audio but has not registered the book. The report calls that file an orphan. After import completes, the button becomes enabled and deletes the now-valid book's audio. Relinking between scan and deletion creates the same class of problem.

**Fix:** coordinate cleanup with import/relink operations and re-fetch current ownership immediately before deletion. Exclude staging locations and recheck containment. Surface failed removals rather than silently treating cleanup as successful.

**Acceptance:** pause an import between copy and registration, build the report, complete import, then confirm deletion; the newly owned file must survive. Also test a report made before relinking.

### S03 — P2: Backup validation does not use the actual application schema

**Evidence:** `Ondelia/Core/Models/SwiftData/DatabaseBackupService.swift:141`; `Ondelia/Core/Models/SwiftData/IsoraSchema.swift`.

The validator constructs an ad hoc schema with five model types. The current schema also includes `CollectionModel` and `ListeningSessionModel`. It opens the backup through a writable ModelContainer without the application's migration plan, and treats opening as sufficient validation.

This does not establish that collections and listening history survive a restore. Depending on migration behavior, opening with a reduced schema can reject a valid backup or alter its schema. Actual entity loss was not experimentally demonstrated here; the confirmed defect is validating against a different data model and potentially modifying the backup under validation.

**Fix:** validate using the exact versioned schema and migration policy on a disposable copy, preserving the original archive. Verify representative data from every root entity, rather than only container construction.

**Acceptance:** populate all seven model types, back up, restore into an isolated location, and compare identifiers, relationships and values. Include a store from each supported released schema version.

### S04 — P2: Database snapshots omit externally stored cover data

**Evidence:** `Ondelia/Core/Models/SwiftData/DatabaseBackupService.swift:32`, `:104`; `Ondelia/Core/Models/SwiftData/AudiobookModel.swift:18`.

`VACUUM INTO` produces a consistent SQLite file, which is an improvement over separately copying a live database and journals. However, `coverImageData` uses `@Attribute(.externalStorage)` and the backup only packages the SQLite file. Externally stored values reside adjacent to the model store, outside the SQLite snapshot. [Apple's attribute options](https://developer.apple.com/documentation/swiftdata/schema/attribute/option).

**Impact:** a backup is not self-contained for covers that SwiftData externalizes. Restoring after the original support files are unavailable cannot be assumed to restore those images. Small inline values may hide this defect in simple fixtures.

**Fix:** use a coordinated complete-store backup or an explicit logical export/import that includes external binary values. State clearly that original audiobook media is separate from database backup protection.

**Acceptance:** use large cover blobs, remove access to the original store/support directory, restore, and compare image bytes. The restored library must not depend on the original location.

### S05 — P2: Interrupted Watch queue states can remain stuck after relaunch

**Evidence:** `Ondelia/Core/Services/Watch/WatchTransferQueue.swift:16`, `:86`, `:94`; `Ondelia/Core/Services/Watch/WatchSyncService.swift`; `WatchSyncService+Transfers.swift`.

The queue persists `.exporting` and `.sending` states, restores them unchanged, and selects only `.queued` rows for work. Enqueuing an existing item only resets a failed row. Activation drains the queue but does not reconcile persisted states with actual WatchConnectivity transfers.

**Failure scenario:** terminate the phone process during export. After relaunch the entry still says exporting; it is never selected and another request does not requeue it. Sending rows can likewise become stale if the matching transfer no longer exists.

**Fix:** recover the state machine at activation: requeue interrupted exports, reconcile sending entries with `outstandingFileTransfers` and receiver inventory, and discard obsolete staging files safely.

**Acceptance:** terminate at export, staging, transfer submission and callback boundaries. Relaunch must converge to delivered or explicitly retriable state without duplicate inventory entries.

### S06 — P2: Watch export has no background-expiration cancellation path

**Evidence:** `Ondelia/Core/Services/Watch/WatchSyncService+Transfers.swift:60`; `Ondelia/Core/Services/Watch/WatchAudioExporter.swift:143`.

The export starts a UIKit background task without an expiration handler. The reader/writer pump also polls `isReadyForMoreMediaData` with sleeps, without checking cancellation or writer failure inside that wait. Long exports can outlive the allowed background execution time, or remain waiting when the writer cannot progress.

**Impact:** system termination can interrupt export and feed the stuck-state problem in S05. A background assertion is not permission to run an arbitrarily long export. [Apple background task guidance](https://developer.apple.com/documentation/uikit/uiapplication/beginbackgroundtask(expirationhandler:)).

**Fix:** cancel the reader/writer on expiration, persist a retriable queue state, and end the assertion on every exit. Prefer readiness-driven writing with explicit cancellation and terminal-state handling.

**Acceptance:** inject writer failure and cancellation while waiting for readiness; then exercise expiration on a physical device. No unbounded wait or stranded queue entry should remain.

### S07 — P2: Watch bookmarks acquire a second identity on the phone

**Evidence:** `Ondelia/Core/Services/Watch/WatchSyncService+Progress.swift:89`; `Ondelia/Core/Managers/AudiobookManager.swift:103`; `OndeliaWatch Watch App/Sync/PhoneSyncService+Snapshot.swift:95`.

The phone checks for the received bookmark UUID, then calls a creation helper that generates a new UUID and creation date. The next phone snapshot therefore carries a different bookmark identity. The Watch merges by UUID and keeps the original entry, so the round trip can create a duplicate. Repeated delivery also bypasses the phone's intended deduplication.

**Fix:** insert or upsert with the received UUID and creation date. Keep remote data application separate from creation of a new local bookmark.

**Acceptance:** deliver the same Watch bookmark twice and perform phone-to-Watch snapshot round trips. Exactly one bookmark with the original identity and date must remain on each device.

### S08 — P2: Failed Watch cover transfers are permanently marked delivered

**Evidence:** `Ondelia/Core/Services/Watch/WatchSyncService+Snapshot.swift:116`, `:129`; `Ondelia/Core/Services/Watch/WatchSyncService+Transfers.swift:124`.

The cover digest is saved in `watchSentCovers` immediately after transfer submission. The completion path only handles chapter metadata, so a failed cover transfer leaves the digest unchanged and future snapshots skip the same cover.

**Fix:** track pending versus successfully delivered covers, acknowledge only successful delivery, and reconcile against the currently paired Watch or receiver inventory. Clear stale delivery assumptions after Watch reinstall/replacement.

**Acceptance:** fail a cover transfer, relaunch, and retry with unchanged cover data; verify eventual receipt. Repeat with an empty receiver inventory.

### S09 — P2: Transcription replacement can start multiple jobs after an await

**Evidence:** `Ondelia/Core/Services/SpeechTranscriptionManager.swift:100`.

`transcribe` cancels the current job, awaits it, then installs a new job. Actor isolation does not serialize the entire operation across that suspension. Two callers can both await the same old job and both create replacement jobs after it ends. There is no cancellation/ownership check between the await and task creation.

**Failure scenario:** rapid language/window changes while the previous analyzer is stopping. Multiple callers can resume and launch competing analyses even though only one remains referenced by `current`. Existing view guards help prevent stale display updates but do not enforce the service's single-active-job invariant.

**Fix:** assign a request generation before suspension, check cancellation and ownership after suspension, and scope shared state updates to the owning generation. Ensure cancelled callers cannot launch new analyzers.

**Acceptance:** hold the first job at a controllable cancellation barrier, enqueue two replacements, release the barrier, and verify only the latest request starts and can publish state.

### S10 — P2: Finished Hardcover books bypass throttling and rewrite the finish date

**Evidence:** `Ondelia/Core/Services/HardcoverService+Progress.swift:74`, `:108`.

The normal progress threshold applies only when `isFinished` is false. Finished books always send progress, with `finishedAt` derived from today's date. Replaying a book that remains marked finished can therefore issue updates on each five-second progress cycle and overwrite its earlier finish date. Status-update failures also lack a retry backoff in this path.

**Fix:** model completion as a persisted event, preserve its date, and deduplicate successful completion pushes. Apply bounded retry/backoff independently from position changes, including status and edition lookup failures. Define explicit reread behavior.

**Acceptance:** finish on day A, replay on day B, and verify that the original completion date stays intact unless a new read is intentionally created. Simulate an outage and verify bounded request frequency. No live Hardcover writes were made during this audit.

### S11 — P2: Playback does not recover from a media-services reset

**Evidence:** `Ondelia/Core/Managers/GlobalAudioManager+AudioSession.swift:15`; `Ondelia/Core/Managers/GlobalAudioManager.swift:39`.

Session activation is gated by `hasActivatedAudioSession`, but no observer for `mediaServicesWereResetNotification` was found. After a media-server reset, that flag can remain set while the underlying audio objects and session need rebuilding.

**Fix and acceptance:** invalidate activation state, recreate affected audio objects and restore configuration; validate with the system media-services reset on a device, preserving position and waiting for user action before resuming. See [AUDIO_AUDIT.md](AUDIO_AUDIT.md) for supporting Apple references and the wider routing matrix.

### S12 — P3: Image-search terms are not encoded as individual query values

**Evidence:** `Ondelia/Core/Services/GoogleImageSearchService.swift:43`.

The query uses `.urlQueryAllowed` and is interpolated into a URL containing other parameters. That character set permits separators such as `&`, so a title such as `War & Peace` can become more than one URL parameter rather than one search term.

**Fix:** build the URL with `URLComponents` and `URLQueryItem` for every parameter.

**Acceptance:** inspect constructed URLs for ampersands, plus signs, hashes, non-Latin text and spaces; the server-decoded `q` value must equal the original query. No real search credentials need to be sent to verify this.

## iOS 26 and large-file assessment

The transcription design already avoids decoding an entire 1 GB audiobook before producing a window. `AudioWindowSequence` seeks to the window start and yields at most 32,768 source frames per pull, converting incrementally. `SpeechTranscriptionManager` uses the iOS 26 SpeechAnalyzer family and window-based caching. These choices are appropriate foundations for keeping working memory tied to the active window.

Language selection is explicit, with fallback through declared media locale and the device locale; this should not be marketed as acoustic language autodetection. Keep the language picker. The current view result guards and default selection are improvements, while S09 addresses a separate service-level race.

File size alone does not predict transcription latency: codec seeking, window duration, first-time model preparation, channel conversion, and device thermal state matter. No 1 GB fixture or Instruments run was available in this audit, so there is no measured latency or memory improvement to report.

Recommended measurements:

- Record source-open/seek, model preparation, first transcript, final transcript and cancellation latency separately.
- Use short and long MP3/M4B files, including a real 1 GB book, seeking near the beginning and end; compare cold versus warm model/cache runs.
- Switch language and windows repeatedly during analysis, including dismissal and backgrounding; verify bounded active analyzer count and memory recovery.
- Profile libraries with many tracks and large listening histories. Queue construction and computed statistics can scale with collection size; establish their actual main-thread cost before optimizing.
- Use file-generation identity for transcript cache invalidation when media is replaced or relinked; matching a path/name and duration does not prove identical content.

On-device analysis and explicit cancellation remain sound API choices. Apple's [SpeechAnalyzer cancellation documentation](https://developer.apple.com/documentation/speech/speechanalyzer/cancelandfinishnow()) describes immediate finishing of pending analysis; lifecycle control must still be correct around concurrent callers.

## Practices worth retaining

- Streaming import copies preserve original audio and avoid whole-file allocation.
- ZIP extraction has path-containment checks, symlink rejection and expansion limits; cleanup retains the exact extraction root. The earlier broad-parent cleanup concern is not carried forward as a current defect.
- SQLite backup creation uses `VACUUM INTO`, avoiding an inconsistent independently copied database/WAL pair. S01, S03 and S04 concern the remaining restore/validation/package boundaries.
- Store-load failures preserve files and expose retry/error UI rather than silently deleting the database. Save failures are surfaced.
- Watch incoming files are moved to owned storage before the connectivity callback returns. Snapshot progress throttling is already present.
- Keychain storage is used for credentials; inspected logging avoids printing token values. Hardcover requests use HTTPS and structured GraphQL variables with response/error handling.
- CarPlay limits rendered rows and downsamples cover images. Its initial population waits for store loading.
- The project uses Swift 6 and OS 26 deployment targets. Retained Isora module identifiers are deliberate compatibility identities; renaming them casually could affect persisted types. Their presence alone is not a branding defect.

## Validation performed

Executed against the current checkout:

```sh
xcodebuild test -project Ondelia.xcodeproj -scheme Ondelia \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/ondelia-solution-audit \
  -only-testing:OndeliaTests \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
```

**Result: TEST SUCCEEDED — 205 tests in 40 suites passed.** The Swift Testing run reported 8.994 seconds. Build warnings included redundant `#require` usage in `CollectionGroupTests` and an App Intents metadata-extraction warning; no build failure occurred.

Local evidence, temporary and not committed:

- `/tmp/ondelia-solution-audit-tests.log`
- `/tmp/ondelia-solution-audit/Logs/Test/Test-Ondelia-2026.09.12_11-54-55-+0200.xcresult`

This run selected iPhone unit/integration tests. It does not establish Watch runtime behavior, UI correctness, physical-device performance, accessibility, leak freedom or release-signing validity. The findings above were established by source inspection; destructive restore, interrupted transfer, cloud-account and hardware failure scenarios were not run against user data.

## Release validation still needed

| Validation | Concrete objective |
| --- | --- |
| Recovery fixtures | Restore complete stores from supported releases, including external blobs, with injected filesystem failures |
| Paired phone/Watch | Kill/relaunch at each transfer stage, fail delivery, reinstall receiver, verify bookmark identity and progress convergence |
| CloudKit | Two-device offline edits, deletion/reimport, restore reconciliation and schema deployment in a test environment |
| Playback hardware | Interruptions, route changes, media reset, lock-screen controls, rate changes and Atmos reference content |
| UI/accessibility | Library/import/player/settings/onboarding at large text sizes with VoiceOver; Watch, widget and CarPlay interactions |
| Integrations | Mocked outage/retry and completion-date behavior; StoreKit pending/interrupted purchase lifecycle |
| Archive/compliance | Release archive, extension signing, entitlement provisioning and aggregated privacy manifest / required-reason API review |
| Performance | Real 1 GB files, many-track books and large histories under Instruments, including background/thermal conditions |

The inspected privacy manifests primarily declare UserDefaults reasons. This audit does not certify that the aggregate archive covers every required-reason API used by the app and dependencies; complete that check on the shipping archive rather than infer compliance from a source manifest alone.

## Suggested implementation order

1. **Protect data:** S01 and S02, followed by S03/S04 as one complete backup/recovery design.
2. **Make Watch delivery recoverable:** S05/S06, then S07/S08 for identity and acknowledgment.
3. **Fix async/integration correctness:** S09/S10 and S11.
4. **Polish narrow behavior:** S12, then measured large-library improvements and the release-validation matrix.

Keep the existing passing suite and add focused regression scenarios when implementing each fix. The current green test result is useful baseline evidence, not a substitute for exercising recovery and cross-device failures.
