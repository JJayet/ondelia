# Server audiobooks are shown alongside the Library, not added to it

With "Show server audiobooks in Library" on, every server audiobook of the selected server library appears on the Library screen, in Search and in Collections as if it were part of the Library, but no record is created for it until it joins: on first stream, download, or the first listener action that needs one (added to a Collection or Up Next, bookmarked, marked finished). Creating records for the whole server library would push thousands of entries through iCloud to every device, fill the listening statistics with audiobooks never played, and leave records to reconcile whenever the server changes; the server already holds that catalogue, so Ondelia fetches it and blends it in memory.

## Consequences

- A server series becomes a Collection once the Library holds one of its audiobooks, but its members are read live from the server rather than stored, so it can list server audiobooks that have not joined. Auto-continue onto one streams it, which makes it join.
- When the server is unreachable, signed out, or the setting is off, server audiobooks vanish and so do streamed audiobooks: only audiobooks with audio on the device (and those with missing audio) are shown. Streamed audiobooks keep their records and reappear when the server returns.
- A duplicate between an imported audiobook and a server audiobook is resolved by giving the imported one a server link, never by matching titles automatically.
