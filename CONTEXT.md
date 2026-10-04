# Ondelia

An iOS audiobook player for listening to audiobooks imported from files or streamed and downloaded from an AudiobookShelf server.

## Language

**Audiobook**:
One title the listener plays, from one or more audio files, with its own position, chapters and bookmarks.
_Avoid_: Book, title, item

### Organising

**Library**:
Every audiobook this device keeps a record of: imported from files, downloaded from a server, or streamed from one at least once.
_Avoid_: Shelf

**Server**:
An AudiobookShelf server the listener signed in to, known by its address and username. The listener can sign in to several; each has its own selected server library and can be shown in the Library or not.
_Avoid_: Account, instance, source

**Server library**:
One of the libraries an AudiobookShelf server divides its audiobooks into. Always qualified; bare "Library" means this device's Library.
_Avoid_: Library (unqualified), source

**Server audiobook**:
An audiobook on an AudiobookShelf server. It joins the Library when it is downloaded, first streamed or first acted on (added by the listener to a Collection or Up Next, bookmarked, marked finished), and stays linked to its server original. The listener can choose to see the server audiobooks of each shown server's selected server library alongside the Library; seeing one there does not make it join.
_Avoid_: Item, server book

**Server link**:
The tie between a Library audiobook and its server audiobook. It is made when a server audiobook joins, or by the listener on an imported audiobook that is the same recording; a server audiobook with a server link is never shown twice.
_Avoid_: Relink, match

**Server series**:
A series as an AudiobookShelf server groups its server audiobooks. While the listener sees server audiobooks alongside the Library, every server series of each shown server library appears among the Collections; it becomes a Collection once the Library holds one of its audiobooks, its members being whatever the server lists. Always qualified; bare "Series" means the Hardcover-backed Collection.
_Avoid_: Series (unqualified)

**Server collection**:
A collection as an AudiobookShelf server keeps it: a named, ordered list of its server audiobooks, edited on the server only. It appears and becomes a Collection the way a server series does.
_Avoid_: Server playlist, shared collection

**Hidden**:
The state of a server audiobook, server series, server collection or author the listener chose not to see: it appears nowhere in Ondelia, on any of their devices, until shown again. Hiding an author hides their server audiobooks too; hiding a series or collection does not. Hiding never removes anything from the server or the Library.
_Avoid_: Ignored, excluded, blocked

**Streamed audiobook**:
A Library audiobook whose audio stays on the server and plays over the network.
_Avoid_: Remote book, online book

**Downloaded audiobook**:
A Library audiobook whose audio came from a server and is now held on this device.
_Avoid_: Offline book

**Collection**:
A named, ordered group of Library or server audiobooks; an audiobook can belong to any number of them. Server audiobooks in a Collection stay outside the Library until they join.
_Avoid_: Shelf, list, playlist

**Series**:
A Collection linked to a Hardcover series, ordered by volume, which may list volumes the Library does not hold.
_Avoid_: Saga, cycle

### Listening

**Listener**:
The person using Ondelia to play audiobooks.
_Avoid_: User, reader

**Listening session**:
One unbroken stretch of playing a single audiobook, measured in wall-clock time; short pauses do not end it.
_Avoid_: Reading session, play

**Listening log**:
The append-only history of every listening session, kept even after the audiobook leaves the Library. All statistics derive from it.
_Avoid_: History, reading log

**Finish**:
One completion of an audiobook, recorded in the listening log when playback reaches the end or the listener marks it finished. A re-listen to the end is another Finish; unmarking retracts the most recent one. A remote report of the same completion is not a second Finish.
_Avoid_: Completion, read

**Finished**:
The state of an audiobook whose latest Finish has not been retracted.
_Avoid_: Read, completed, done

**Up Next**:
The listener's ordered list of audiobooks to play after the current one, consumed from the front.
_Avoid_: Queue, play queue, playlist

**Auto-continue**:
A Collection setting under which, when one of its audiobooks ends, the next unfinished one in the Collection plays. It takes precedence over Up Next, which resumes once the Collection has nothing left.
_Avoid_: Chaining, autoplay

### Timeline

**Position**:
How far into an audiobook the listener is, as a time on the audiobook's whole timeline. One position per audiobook, shared across the listener's devices and any linked server.
_Avoid_: Progress, offset, current time

**Chapter**:
A titled span of an audiobook's timeline. Chapters are independent of how the audio is split into files.
_Avoid_: Track, part, file

**Bookmark**:
A position in an audiobook the listener saved on purpose, optionally titled and annotated.
_Avoid_: Clip, highlight, marker

**Transcript**:
The text of what is spoken in a stretch of an audiobook, timed word by word against the audio and produced on the device.
_Avoid_: Transcription, captions, subtitles

### Import

**Import**:
Bringing audio from files, a folder, an archive or the Inbox into the Library, as one or more audiobooks.
_Avoid_: Add, upload

**Inbox**:
The drop box where files shared to Ondelia from other apps, AirDrop or Finder wait until the next import picks them up.
_Avoid_: Downloads, incoming

**Missing audio**:
The state of a Library audiobook with no audio on this device and no server to stream it from, such as one synced from another device or whose file was deleted. It keeps its position, chapters and bookmarks.
_Avoid_: Placeholder, broken, unavailable

**Relink**:
An import that supplies the audio of an audiobook with missing audio, instead of creating a new audiobook.
_Avoid_: Restore, reattach, re-import

**Merge**:
Combining several Library audiobooks into one, each becoming a chapter in order; it reassembles an audiobook that arrived split into one file per chapter. The listener's position, bookmarks and Collection and Up Next membership carry over onto the combined timeline.
_Avoid_: Join, combine, concatenate

### Hardcover

**Hardcover book**:
A book in Hardcover's catalogue, independent of any format; it groups the editions Hardcover knows for it.
_Avoid_: Work, title

**Hardcover link**:
The match between a Library audiobook and the Hardcover book it is a recording of. An audiobook has at most one.
_Avoid_: Match, binding

**Hardcover status**:
Where a linked audiobook sits on the listener's Hardcover profile: want to read, reading, or read, or kept in Ondelia only. It only ever moves forward.
_Avoid_: Shelf, reading status

**Edition**:
The audiobook edition of a Hardcover book that progress is measured against, chosen as the one closest in length to the audiobook.
_Avoid_: Version, release

**Hardcover read**:
One read-through recorded on Hardcover, carrying its progress and dates. Each Finish closes one; listening again after a Finish opens the next.
_Avoid_: Listen, session

**Declined series**:
A Hardcover series the listener removed as a Collection, which is never offered as a Collection again. Removing a server series Collection hides the server series instead.
_Avoid_: Hidden series, ignored series

### Statistics

**Listening day**:
A calendar day on which at least one listening session with real listening time started.
_Avoid_: Active day, reading day

**Streak**:
A run of consecutive listening days. It stays unbroken until a whole day passes with no listening.
_Avoid_: Chain, run

**Monthly goal**:
The listening time the listener aims for in a calendar month. It belongs to the listener, so it is the same on every device.
_Avoid_: Target, objective

**Milestone**:
A badge the listener earns by crossing a threshold in the listening log, such as Finishes, hours or streak length. Once earned, it stays earned.
_Avoid_: Achievement, trophy, award

**Night Owl**:
The milestone for listening time started between 21:00 and 05:00.

**Early Bird**:
The milestone for listening time started between 05:00 and 08:00. Time never counts towards both Night Owl and Early Bird.
