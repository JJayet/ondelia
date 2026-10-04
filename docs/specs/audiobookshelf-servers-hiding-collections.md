# Spec: several servers, hiding, server collections, Collections screen

Status: implemented except the Collections screen (#28) · 2026-10-04. Issue #29.

## Decisions taken

| Topic | Decision |
|---|---|
| Several servers | All signed-in servers are blended into the Library at once (extends ADR 0002). |
| Hidden scope | Synced through iCloud: hiding on one device hides on all. |
| Hide vs Delete | Hide replaces Delete only for server audiobooks with no audio on the device. |
| Server collections | Read-only mirror of the server; edits happen on the server. |
| Hidden in Search | Hidden entries never appear in Search. |
| Hidden author | Hides the author and all their books. |
| Watch | Several servers on the Watch ship in the same release. |
| Port | Each server has an optional Port field, separate from the address. |

## Current state (what assumes one server)

- `AudiobookShelfService` holds one `server`, `token`, `username`, `selectedLibrary`
  (UserDefaults + Keychain `audiobookshelf.token`); ~65 call sites read `.shared`.
- `AudiobookShelfCatalog` fetches one server library's items and series.
- `AudiobookShelfLinkModel` stores `itemID` only, no server.
- Downloads are keyed by item id (`AudiobookShelfDownloader.parse`, `pendingDownloads` folders).
- Watch receives one `ServerAccount` (`WatchSyncService.sendServerAccount`).
- `AudiobookShelfCatalog.collectionID(forSeries:)` derives Collection ids from the series id.
- Removing a server series Collection adds it to `declinedServerSeries` (UserDefaults, per device).

## Phase 0 — Server identity (prerequisite, no visible change)

Everything after needs to know which server an id belongs to.

- **Server id**: derived, not generated: UUID v5-style hash of `normalized server URL + username`,
  the same trick as `collectionID(forSeries:)`. Every device computes the same id with no
  coordination, so links and hidden records agree across devices.
- **Port**: the sign-in form gets an optional Port field (1–65535). It overrides any port typed
  in the address; `serverURL(from:port:)` builds the URL. The id hashes the resulting URL, so
  `host` and `host:443` over https normalise to the same id (default ports dropped).
- **Accounts list**: `[ServerAccount { id, server, username, selectedLibrary, showsInLibrary }]`
  as JSON in UserDefaults, synced by `SettingsSync`. Token in Keychain under
  `audiobookshelf.token.<id>`, synchronizable as today.
- **Migration of the single account**: on first launch, the existing keys become the first
  account; the old keys are read once, then removed.
- **Schema V6** adds two entities (model classes are shared across versions, so no existing
  model can gain a column without breaking shipped stores; see `IsoraSchema.swift`):
  - `AudiobookShelfItemServerModel { itemID, serverID }`: which server an item lives on, written
    beside every link. Links without one (made before, or by a device on an older version) are
    backfilled to the first server on each library fetch; two devices write the same pairs.
  - `HiddenServerEntryModel` (Phase 1).
- **Older versions on other devices**: the first account is still mirrored into the
  single-account keys (`audiobookshelf.server`, `.username`, `.library`, `.token`).
- `collectionID(forSeries:)` stays unchanged: AudiobookShelf series ids are UUIDs, so they do
  not collide across servers, and changing the formula would orphan stored Collections.

Tests: server id stability (URL normalisation, trailing slash, case); Port field; legacy
migration; pinned entity hashes.

## Phase 1 — Hiding

### Model

```swift
@Model final class HiddenServerEntryModel {
    var serverID: String = ""
    var kind: String = ""      // book | series | collection | author
    var entityID: String = ""  // AudiobookShelf id
    var name: String = ""      // shown in Settings without fetching
    var hiddenAt: Date = Date()
}
```

Duplicates (two devices hide the same thing) are harmless; unhide deletes every match.

### What hiding does

| Kind | Effect |
|---|---|
| Book | Gone from the Library blend, Search and the AudiobookShelf browser. Opening a server series still lists it: that screen shows the series as the server has it. |
| Series | Gone from Collections. Its books stay unless hidden themselves. |
| Collection | Gone from Collections (Phase 3). |
| Author | Gone from the Authors browse list and Search, and **all their books are hidden** too. |

Hiding a series or collection never hides its books. Hiding an author does: a book is hidden
when it, or any of its authors, is hidden. Hidden by author shows in Settings as
"Hidden with <author>" and is unhidden only by showing the author again.

Hiding never touches a Library audiobook that has audio on the device.

### Book menu

| Audiobook state | Actions |
|---|---|
| Server audiobook, not joined | **Hide** |
| Streamed audiobook (joined, no audio here) | **Hide** replaces Delete. Record, position, bookmarks kept; reappears when unhidden. |
| Downloaded audiobook | **Remove Download** (becomes streamed) + **Delete** |
| Imported audiobook | **Delete** (unchanged) |

Series/collection cards and author rows get **Hide** in their context menu.

### Declined series

Removing a server series Collection now hides the series instead of declining it.
`declinedServerSeries` entries are migrated into `HiddenServerEntryModel` once, then the key is
removed. "Declined series" stays for Hardcover series only.

### Settings

AudiobookShelf settings → server → **Hidden & Shown**: four segments (Books, Series,
Collections, Authors). Each lists the server's entries with a search field and a toggle per row;
a "Hidden only" filter shows just what is hidden. Books lists can be thousands of rows: lazy list,
search over the in-memory catalogue.

Tests: catalogue filtering per kind; menu actions per state; declined-series migration.

## Phase 2 — Collections screen

The Library gets crowded because every Collection and server series is a full-height card
above the books.

- Library keeps one **Collections** strip: a horizontal row of at most ~8 tiles (in-progress
  first, then recently played), with **See All**.
- **See All** pushes a Collections screen: segmented filter (All · Mine · Series · Server),
  search, sort (name, recent, progress), list/grid like the Library.
- The folded "Server series" row (`serverSeriesToggle`) goes away; server series live in the
  Collections screen.
- Wide layout: same strip, the screen uses the existing tiles.

Pushed screen rather than a new tab: the tab bar stays Library + Search, and Collections are a
way into the Library, not a separate place. Revisit if usage says otherwise.

## Phase 3 — Server collections

- **Server collection** (new glossary term): a collection as an AudiobookShelf server keeps it.
  Fetched with the catalogue: `GET /api/libraries/<id>/collections`.
- Treated like a server series (ADR 0002): drawn from the catalogue, stored as a Collection
  only once the Library holds one of its audiobooks. Id:
  `collectionID(forServerCollection:)` hashing `"audiobookshelf-collection:<id>"`.
- Not written back: members are the server's. Once stored as a Collection it behaves like a
  stored server series (the listener's order, new members on the end). Auto-continue works.
- Listed unfolded, above the folded server series: a server has few, chosen by hand.
- Playlists: out of scope.

Tests: decoding, id derivation, read-only actions hidden.

## Phase 4 — Several servers

- **Catalogue**: one `AudiobookShelfCatalog` per account with `showsInLibrary` on, fetched in
  parallel; the Library merges their entries with today's `LibraryEntry.merged`.
  `LibraryEntry.server` carries the account id.
- **Every server call** takes the account: streaming, downloads, progress push to the book's own
  server (via `AudiobookShelfLinkModel.serverID`), item menus, covers.
- **Downloads**: task description and pending-download folder gain the account id; legacy
  entries without one belong to the migrated account.
- **Unreachable**: per server. One server down hides only its books (ADR 0002 rule, per server);
  the unreachable button lists which.
- **Search**: queries every shown server, results grouped by server only when more than one.
- **Same book on two servers**: two server audiobooks, both shown. Not deduplicated.
- **Settings**: AudiobookShelf settings becomes a list of servers + Add Server. Each server:
  account, server library, Show in Library, Hidden & Shown, Sign Out.
- **Watch** (ADR 0003): sends the account list; the Watch's Server screen picks a server first.
  `joined` events carry the account id. Ships in the same release.

Tests: merge across catalogues; progress routed to the right server; per-server unreachable.

## Order and size

| Phase | Depends on | Size |
|---|---|---|
| 0 Server identity | — | S, but schema migration: test on a CloudKit dev container |
| 1 Hiding | 0 | M |
| 2 Collections screen | — | M (separate issue, deferred) |
| 3 Server collections | 0 | S–M |
| 4 Several servers | 0 | L |

Hiding and the Collections screen fix the crowding now; several servers is the largest and
goes last.

## Docs to update when shipping

- `CONTEXT.md`: **Server** (an AudiobookShelf account, identified by URL + username),
  **Hidden** (a server audiobook, server series, server collection or author the listener chose
  not to see), **Server collection**; narrow **Declined series** to Hardcover.
- ADR 0004: several servers blended; derived server id.
- ADR 0002: "selected server library" becomes "each shown server's selected server library".
- `CHANGELOG.md` for the version that ships each phase.
