# Several servers are blended into one Library, each known by a derived id

The listener can sign in to several AudiobookShelf servers at once, and every server they mark as shown has its selected server library blended into the Library, Search and Collections, as one server's was (ADR 0002). Switching between servers was the other option; it was rejected because a listener with a home server and a family member's server thinks of both as one collection of audiobooks, and switching would hide half of it, Continue Reading included.

Each server is identified by a hash of its normalised address and username, not by a generated id. Every device then derives the same id for the same server without agreeing on it first, so the records that name a server (which server an item lives on, what is hidden) mean the same thing everywhere, and signing in again gives back the same id.

## Considered options

- **One active server, switched in Settings.** Simpler: mostly a picker over the single-server code. Rejected for the reason above.
- **A generated id per server, synced.** Two devices signing in before iCloud brings each other's list would make two ids for one server, and records naming either would have to be reconciled.

## Consequences

- Item ids are UUIDs, unique across servers, so a server audiobook, server series or server collection is still keyed by its own id; which server it lives on is a lookup (the catalogue for shown ones, `AudiobookShelfItemServerModel` for linked ones), not part of the key. Collection ids derived from server series stay as they were.
- Model classes are shared between schema versions, so a link cannot gain a server column: the server of an item is its own entity, written beside each link and backfilled to the first server for links made before.
- The first server is still written to the single-server keys, so a device on an older version keeps working with it.
- A server that does not answer drops only its own audiobooks; the others stay.
- The same audiobook on two servers is two server audiobooks; nothing deduplicates them.
- The Watch receives every server and browses one at a time.
