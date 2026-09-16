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
    var syncing: Set<UUID> = []

    /// How much book time must pass before the position is pushed again. Progress is written
    /// locally every five seconds, which is not a rate any server should be told about.
    static let progressPushInterval = 60

    /// Position at the last push *attempt* per book, so a paused book is not re-sent on every
    /// tick and a failing one is not retried on every tick either. In memory only: the cost of
    /// forgetting it is one redundant request after a launch.
    var attemptedSeconds: [UUID: Int] = [:]

    private init() {}

    // MARK: - Settings

    /// The bare key. A pasted "Bearer …" loses its scheme here; `HardcoverAPI` puts it back
    /// on every request, so the reader only ever pastes the key itself.
    var token: String? {
        get { Keychain.get(Self.tokenKey) }
        set {
            var value = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let v = value, v.lowercased().hasPrefix("bearer ") {
                value = String(v.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            }
            Keychain.set(value, for: Self.tokenKey)
        }
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
        guard force || link.detailsChecked != true || link.releaseDateChecked != true else { return }

        do {
            let details = try await HardcoverAPI.details(bookID: link.id, token: token)
            // Re-read: an await let the book be unlinked or relinked while the request was out.
            guard var current = audiobook.hardcover, current.id == link.id else { return }
            current.summary = details?.summary
            current.genres = details?.genres
            current.moods = details?.moods
            current.contentWarnings = details?.contentWarnings
            current.releaseDate = details?.releaseDate
            current.detailsChecked = true
            current.releaseDateChecked = true
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
            let options = try await HardcoverAPI.seriesOptions(bookID: link.id, token: token)
            // Re-read: an await let the book be unlinked or relinked while the request was out.
            guard let current = audiobook.hardcover, current.id == link.id else { return }
            let series = Self.choose(from: options, keeping: current.seriesID)
            apply(series, to: audiobook)
            if let series { await refreshCatalog(seriesID: series.id, force: force) }
        } catch {
            Log.hardcover.error("Failed to read series: \(error.localizedDescription)")
        }
    }

    /// The series already on the link when Hardcover still lists it — a hand pick, or last
    /// time's answer — else the featured one (first in `options`). No stored flag for the pick:
    /// `HardcoverLink` is flattened into the store's entity, so a new field changes the schema.
    nonisolated static func choose(from options: [HardcoverAPI.SeriesRef], keeping seriesID: Int?) -> HardcoverAPI.SeriesRef? {
        options.first { $0.id == seriesID } ?? options.first
    }

    /// Every series Hardcover lists the linked book in, featured first. For the picker.
    func seriesOptions(for audiobook: AudiobookModel) async -> [HardcoverAPI.SeriesRef] {
        guard let token, let link = audiobook.hardcover else { return [] }
        do {
            return try await HardcoverAPI.seriesOptions(bookID: link.id, token: token)
        } catch {
            Log.hardcover.error("Failed to read series: \(error.localizedDescription)")
            return []
        }
    }

    /// The listener's pick among a book's series. Kept across refreshes while Hardcover lists it.
    func setSeries(_ series: HardcoverAPI.SeriesRef, for audiobook: AudiobookModel) async {
        apply(series, to: audiobook)
        await refreshCatalog(seriesID: series.id)
    }

    private func apply(_ series: HardcoverAPI.SeriesRef?, to audiobook: AudiobookModel) {
        guard var current = audiobook.hardcover else { return }
        current.seriesID = series?.id
        current.seriesName = series?.name
        current.seriesPosition = series?.position
        current.seriesChecked = true
        audiobook.hardcover = current
        save()
        AudiobookManager.shared.reconcileSeriesCollections()
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

    func save() {
        AudiobookManager.shared.swiftDataController.save()
    }
}
