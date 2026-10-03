# The Watch creates a server audiobook's record, and the phone adopts it

The Watch streams server audiobooks on its own, over Wi-Fi or cellular, away from the phone. Streaming one makes it join the Library, but the phone owns the Library and may be out of reach, so the Watch creates the record itself under a new id and queues a `joined(bookID, itemID)` event. When the phone receives it, it creates the Library record under that same id. If the Library already links that server audiobook, the phone instead maps the Watch's id to its own record, and the Watch switches to the phone's id on the next snapshot. Every later event (position, listening time, bookmarks) then flows as it does for audiobooks the phone sent.

## Considered options

- **Join only through the phone.** The Watch would stream without a Library record and push its position to the server itself. Rejected: it breaks "first stream joins", and listening time on the Watch would never reach the listening log.
- **Sign in on the Watch.** Rejected: typing a server address and password on a wrist. The phone hands over its server, token and selected server library instead, and the Watch keeps the token in its own keychain under its own key.

## Consequences

- The phone keeps the Watch-to-phone id map for good, because events the Watch queued under its own id can arrive at any later time.
- Events about a book whose join is in progress wait on the phone until the record exists. If the join fails (the phone cannot reach the server), they are dropped.
- Position still reaches the server through the phone, so other clients see Watch listening only after the two reconnect.
