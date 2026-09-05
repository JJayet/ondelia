import Foundation
import SwiftData

/// Keeps the library in step with the reader's Hardcover shelves.
///
/// Three jobs: search Hardcover, remember which Hardcover book an audiobook is, and push the
/// reading status when playback crosses "started" or reaches the end. Everything is a no-op
/// until an access token is saved, so callers never have to check first.
@MainActor
final class HardcoverService {
    static let shared = HardcoverService()

    enum Defaults {
        static let autoMatch = "hardcover.autoMatch"
        static let autoAddWantToRead = "hardcover.autoAddWantToRead"
        static let readingThreshold = "hardcover.readingThreshold"
        static let lastSync = "hardcover.lastSync"
    }

    private static let tokenKey = "hardcover.token"

    /// Books with a status push in flight. Progress ticks every five seconds, so without this
    /// the tick that crosses the threshold and the next one both insert a shelf row.
    private var syncing: Set<UUID> = []

    private init() {}

    // MARK: - Settings

    var token: String? {
        get { Keychain.get(Self.tokenKey) }
        set { Keychain.set(newValue?.trimmingCharacters(in: .whitespacesAndNewlines), for: Self.tokenKey) }
    }

    var isLinked: Bool { token?.isEmpty == false }

    var autoMatchEnabled: Bool {
        UserDefaults.standard.bool(forKey: Defaults.autoMatch)
    }

    var autoAddWantToRead: Bool {
        UserDefaults.standard.object(forKey: Defaults.autoAddWantToRead) as? Bool ?? true
    }

    /// Percent of a book that counts as started, 1...99.
    var readingThreshold: Double {
        UserDefaults.standard.object(forKey: Defaults.readingThreshold) as? Double ?? 1
    }

    // MARK: - Search

    func search(_ query: String, perPage: Int = 10) async throws -> [HardcoverAPI.SearchHit] {
        guard let token else { return [] }
        return try await HardcoverAPI.search(query, perPage: perPage, token: token)
    }

    /// Search terms for an audiobook: its title with volume numbering stripped, plus the author.
    ///
    /// "Book 3 - The Fellowship" and "03. The Fellowship" are how ripped audiobooks name
    /// themselves; Hardcover indexes neither, and the numbering alone sinks the match.
    nonisolated func searchQuery(for audiobook: AudiobookModel) -> String {
        var title = audiobook.title ?? ""
        let noise = [
            #"(?i)\b(book|part|chapter|volume|vol\.?|tome)\s+\d+\b"#,
            #"(?i)\b\d+\s*-\s*"#,
            #"(?i)^\d+\.\s*"#
        ]
        for pattern in noise {
            title = title.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        title = title
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            // "Book 3 - The Fellowship" leaves its separator behind once the volume goes.
            .trimmingCharacters(in: CharacterSet(charactersIn: " .-–—:"))

        let author = audiobook.author?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return author.isEmpty ? title : "\(title), \(author)"
    }

    // MARK: - Linking

    /// Links `audiobook` to `book`, or clears the link when `book` is nil.
    ///
    /// Clearing takes the book off the Hardcover shelf too, so unlinking a mistaken match does
    /// not leave a stranger's book sitting on the reader's profile.
    func link(_ book: HardcoverLink?, to audiobook: AudiobookModel) async {
        guard let book else {
            if let previous = audiobook.hardcover, let userBookID = previous.userBookID, let token {
                do {
                    try await HardcoverAPI.removeFromShelf(userBookID: userBookID, token: token)
                } catch {
                    Log.hardcover.error("Failed to remove book from shelf: \(error.localizedDescription)")
                }
            }
            audiobook.hardcover = nil
            save()
            return
        }

        var link = book
        if autoAddWantToRead, let token, link.status < .wantToRead {
            do {
                link.userBookID = try await HardcoverAPI.setStatus(
                    bookID: link.id, status: .wantToRead, token: token
                )
                link.status = .wantToRead
            } catch {
                // The local link is still worth keeping: the shelf can be pushed on the next sync.
                Log.hardcover.error("Failed to shelve book: \(error.localizedDescription)")
            }
        }
        audiobook.hardcover = link
        save()
        await refreshSeries(for: audiobook)
    }

    // MARK: - Book details

    /// Pulls the blurb and the reader-applied tags for a linked book.
    ///
    /// Asked for once, the first time the book's detail screen is opened, and stored on the
    /// link: the description does not change, and the screen should not wait on the network
    /// every time it is pushed.
    func refreshDetails(for audiobook: AudiobookModel, force: Bool = false) async {
        guard let token, let link = audiobook.hardcover else { return }
        guard force || link.detailsChecked != true else { return }

        do {
            let details = try await HardcoverAPI.details(bookID: link.id, token: token)
            // Re-read: an await let the book be unlinked or relinked while the request was out.
            guard var current = audiobook.hardcover, current.id == link.id else { return }
            current.summary = details?.summary
            current.genres = details?.genres
            current.moods = details?.moods
            current.contentWarnings = details?.contentWarnings
            current.detailsChecked = true
            audiobook.hardcover = current
            save()
        } catch {
            Log.hardcover.error("Failed to read book details: \(error.localizedDescription)")
        }
    }

    // MARK: - Series

    /// Fills in which series the linked book belongs to, so the library can group it.
    ///
    /// Safe to call on anything: a book with no link, or one whose series is already known, is
    /// skipped without touching the network. Pass `force` to re-ask Hardcover for a book that
    /// came back standalone.
    func refreshSeries(for audiobook: AudiobookModel, force: Bool = false) async {
        guard let token, let link = audiobook.hardcover else { return }
        guard force || link.seriesChecked != true else { return }

        do {
            let series = try await HardcoverAPI.series(bookID: link.id, token: token)
            // Re-read: an await let the book be unlinked or relinked while the request was out.
            guard var current = audiobook.hardcover, current.id == link.id else { return }
            current.seriesID = series?.id
            current.seriesName = series?.name
            current.seriesPosition = series?.position
            current.seriesChecked = true
            audiobook.hardcover = current
            save()

            if let series { await refreshCatalog(seriesID: series.id, force: force) }
        } catch {
            Log.hardcover.error("Failed to read series: \(error.localizedDescription)")
        }
    }

    /// Everything Hardcover knows, for every linked book — what Settings' "Refresh metadata"
    /// runs: the series and its catalogue, the blurb, the tags.
    ///
    /// Sequential, and forcing: this is the button someone presses when the shelf looks stale.
    @discardableResult
    func refreshMetadata(for audiobooks: [AudiobookModel]) async -> (books: Int, inSeries: Int) {
        guard isLinked else { return (0, 0) }
        var refreshed = 0
        var inSeries = 0
        for audiobook in audiobooks where audiobook.hardcover != nil {
            await refreshSeries(for: audiobook, force: true)
            await refreshDetails(for: audiobook, force: true)
            refreshed += 1
            if audiobook.hardcover?.seriesName != nil { inSeries += 1 }
        }
        lastSyncedAt = Date()
        return (refreshed, inSeries)
    }

    /// Series lookup for a whole library — the library's own backfill.
    ///
    /// Sequential on purpose: this walks every linked book, and Hardcover rate-limits.
    @discardableResult
    func refreshSeries(for audiobooks: [AudiobookModel], force: Bool = false) async -> Int {
        guard isLinked else { return 0 }
        var grouped = 0
        for audiobook in audiobooks where audiobook.hardcover != nil {
            await refreshSeries(for: audiobook, force: force)
            if audiobook.hardcover?.seriesName != nil { grouped += 1 }
        }
        lastSyncedAt = Date()
        return grouped
    }

    /// The full volume list for a series, so a card can show what the shelf is missing.
    ///
    /// Cached: the catalogue only changes when Hardcover gains a volume, which is not often
    /// enough to pay for a request on every library read.
    func refreshCatalog(seriesID: Int, force: Bool = false) async {
        guard let token else { return }
        guard force || SeriesCatalog.volumes(for: seriesID).isEmpty else { return }

        do {
            let volumes = try await HardcoverAPI.seriesVolumes(seriesID: seriesID, token: token)
            guard !volumes.isEmpty else { return }
            SeriesCatalog.store(volumes, for: seriesID)
        } catch {
            Log.hardcover.error("Failed to read the series catalogue: \(error.localizedDescription)")
        }
    }

    // MARK: - Status

    /// When the library was last walked against Hardcover, for the Settings row.
    var lastSyncedAt: Date? {
        get { UserDefaults.standard.object(forKey: Defaults.lastSync) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Defaults.lastSync) }
    }

    // MARK: - Progress sync

    /// Pushes the reading status if playback has moved the book past a shelf boundary.
    ///
    /// Called on every progress write, so the cheap guards come first: this only reaches the
    /// network on the tick that crosses the threshold or finishes the book.
    func syncProgress(for audiobook: AudiobookModel) async {
        guard let token, let link = audiobook.hardcover else { return }

        let target: HardcoverLink.Status
        if audiobook.isFinished {
            target = .read
        } else if audiobook.progressFraction * 100 >= readingThreshold {
            target = .reading
        } else {
            return
        }
        guard target > link.status, !syncing.contains(audiobook.id) else { return }

        syncing.insert(audiobook.id)
        defer { syncing.remove(audiobook.id) }

        do {
            let userBookID = try await HardcoverAPI.setStatus(
                bookID: link.id, status: target, token: token
            )
            // Re-read: an await let the book be unlinked or relinked while the request was out.
            guard var current = audiobook.hardcover, current.id == link.id else { return }
            current.status = target
            current.userBookID = userBookID
            audiobook.hardcover = current
            save()
            Log.hardcover.info("Pushed status \(target.rawValue, privacy: .public) to Hardcover")
        } catch {
            Log.hardcover.error("Failed to push status: \(error.localizedDescription)")
        }
    }

    // MARK: - Auto-match

    /// Links freshly imported books to their best search result, when auto-match is on.
    ///
    /// A batch that produces the same Hardcover book twice is left entirely unlinked. Multi-file
    /// rips search alike, and a wrong link is worse than no link: it would mark a book the
    /// reader has not touched as read.
    func autoMatch(_ audiobooks: [AudiobookModel]) async {
        guard isLinked, autoMatchEnabled, !audiobooks.isEmpty else { return }

        var candidates: [(book: AudiobookModel, link: HardcoverLink)] = []
        for audiobook in audiobooks where audiobook.hardcover == nil {
            do {
                guard let hit = try await search(searchQuery(for: audiobook), perPage: 1).first else { continue }
                candidates.append((audiobook, HardcoverLink(hit)))
            } catch {
                Log.hardcover.error("Auto-match search failed: \(error.localizedDescription)")
            }
        }

        while let candidate = candidates.first {
            candidates.removeFirst()
            guard !candidates.contains(where: { $0.link.id == candidate.link.id }) else {
                candidates.removeAll { $0.link.id == candidate.link.id }
                Log.hardcover.info("Skipped an ambiguous auto-match: several books matched one Hardcover id")
                continue
            }
            await link(candidate.link, to: candidate.book)
        }
    }

    private func save() {
        AudiobookManager.shared.swiftDataController.save()
    }
}
