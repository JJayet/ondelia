# iCloud syncs audiobook records, never their audio

The Library syncs across the listener's devices through SwiftData's CloudKit store, but only the records travel: metadata, cover, position, chapters, bookmarks, Collections and the listening log. Audio stays on the device it was imported or downloaded to. Audiobooks are often more than a gigabyte each, so syncing them would burn through the listener's iCloud quota and saturate their connection for files they may never play on that device.

## Consequences

- An audiobook imported on one device shows up on the others with **missing audio** until the listener **relinks** it by importing the same file there. Import matches incoming files against those records instead of creating duplicates.
- Covers are the one blob that does sync: they are small, and a Library full of blank tiles on a second device would look broken.
- Streamed and downloaded audiobooks avoid the problem when an AudiobookShelf server is configured on each device, because the audio has a source other than iCloud.
