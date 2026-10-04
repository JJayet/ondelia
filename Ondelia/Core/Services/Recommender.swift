import Foundation
import FoundationModels

/// "What next?" in at least three picks: the book to continue and the next volume of a series
/// the listener finished a volume of, when there are such, then something different for every
/// slot left.
///
/// The first two are facts the app knows, so it states them itself. Only the third is the
/// model's: Apple's on-device model, which knows little about books by itself, picks it by
/// number from a shortlist of books the listener can already play, with their blurbs. Nothing
/// leaves the device.
@MainActor
enum Recommender {
    struct Pick: Identifiable {
        enum Kind { case resume, nextInSeries, different }

        let kind: Kind
        let candidate: Candidate
        let reason: String
        var id: String { candidate.id }
    }

    static let pickCount = 3
    /// How many books the model reads: they must fit its context with the history and blurbs.
    static let shortlistSize = 30
    static let historySize = 15

    static var isModelAvailable: Bool { SystemLanguageModel.default.isAvailable }

    static func recommend(
        books: [AudiobookModel],
        collections: [CollectionModel],
        server: [AudiobookShelfAPI.Item]
    ) async throws -> [Pick] {
        let history = history(books)
        guard !history.isEmpty else { throw Failure.noHistory }
        let picks = [resume(history), nextInSeries(books: books, collections: collections)].compactMap { $0 }
        let different = try await different(
            count: pickCount - picks.count,
            books: books,
            collections: collections,
            server: server,
            excluding: Set(picks.map(\.id))
        )
        return picks + different
    }

    /// The book most recently played and not finished, past a sample.
    static func resume(_ history: [AudiobookModel]) -> Pick? {
        guard let book = history.first(where: { !$0.isFinished }) else { return nil }
        let reason = String(
            format: NSLocalizedString("%d%% listened · %@ left", comment: "Recommendations: why to continue a book"),
            Int(book.currentPosition / max(book.duration, 1) * 100),
            max(book.duration - book.currentPosition, 0).hoursMinutesFormatted
        )
        return Pick(kind: .resume, candidate: Candidate(book), reason: reason)
    }

    /// The volume after the furthest one played, in the series most recently played, when that
    /// furthest one is finished: never an earlier volume, and never a series still underway
    /// (that is `resume`). A server series counts its server books too, in the server's order.
    static func nextInSeries(books: [AudiobookModel], collections: [CollectionModel]) -> Pick? {
        let groups = CollectionGroup.build(collections: seriesCollections(collections), audiobooks: books, keepEmpty: false)
        var best: (pick: Pick, played: Date)?
        for group in groups {
            let volumes = group.volumes(showMissing: false)
            guard let last = volumes.lastIndex(where: { volume in
                if case .owned(let book) = volume { isStarted(book) } else { false }
            }), case .owned(let furthest) = volumes[last], furthest.isFinished,
                  furthest.lastPlayed > best?.played ?? .distantPast else { continue }
            let next = volumes[(last + 1)...].lazy.compactMap { volume -> Candidate? in
                switch volume {
                case .owned(let book): isStarted(book) ? nil : Candidate(book, series: group.name)
                case .server(let item): Candidate(item)
                case .missing: nil
                }
            }.first
            guard let next else { continue }
            let reason = String(
                format: NSLocalizedString("Next in %@, after %@", comment: "Recommendations: series name, then the volume finished"),
                group.name,
                furthest.title ?? AudiobookModel.unknownTitle
            )
            best = (Pick(kind: .nextInSeries, candidate: next, reason: reason), furthest.lastPlayed)
        }
        return best?.pick
    }

    /// `count` books away from the listener's authors and series, picked by the model. What it
    /// does not fill — out of range, repeated, or no model on this device — the shortlist's
    /// order fills, with a reason the app states.
    static func different(
        count: Int,
        books: [AudiobookModel],
        collections: [CollectionModel],
        server: [AudiobookShelfAPI.Item],
        excluding excluded: Set<String>
    ) async throws -> [Pick] {
        let history = Array(history(books).prefix(historySize))
        let shortlist = differentShortlist(books: books, collections: collections, server: server, excluding: excluded, atLeast: count)
        guard count > 0, !history.isEmpty, !shortlist.isEmpty else { return [] }

        var picks: [Pick] = []
        var taken = Set<Int>()
        if isModelAvailable {
            let language = Locale.current.localizedString(forLanguageCode: Locale.current.language.languageCode?.identifier ?? "en") ?? "English"
            let session = LanguageModelSession(instructions: """
                You suggest audiobooks as a change from what the listener usually plays. Only pick \
                from the numbered candidates. Each reason is one short sentence that names one book \
                from their history and what the two share: a genre or a theme from the blurbs. Never \
                claim a link you cannot see in the lists. Write the reasons in \(language).
                """)
            let generated = try await session.respond(
                to: prompt(history: history, shortlist: shortlist),
                generating: GeneratedPicks.self
            ).content.picks
            // The number is 1-based and only a guide: a model can still go out of range or repeat.
            for pick in generated where picks.count < count {
                guard shortlist.indices.contains(pick.number - 1), taken.insert(pick.number - 1).inserted else { continue }
                picks.append(Pick(kind: .different, candidate: shortlist[pick.number - 1], reason: pick.reason))
            }
        }
        for (index, candidate) in shortlist.enumerated() where picks.count < count && !taken.contains(index) {
            picks.append(Pick(kind: .different, candidate: candidate, reason: statedReason(candidate, history: history)))
        }
        return picks
    }

    /// A genre the candidate shares with a book played, or that it is a change of author.
    static func statedReason(_ candidate: Candidate, history: [AudiobookModel]) -> String {
        for book in history {
            let genres = book.hardcover?.genres ?? []
            if let genre = candidate.genres.first(where: { genre in genres.contains { $0.caseInsensitiveCompare(genre) == .orderedSame } }) {
                return String(
                    format: NSLocalizedString("%@, like %@", comment: "Recommendations: a shared genre, then a book the listener played"),
                    genre,
                    book.title ?? AudiobookModel.unknownTitle
                )
            }
        }
        return NSLocalizedString("A change from your usual authors", comment: "Recommendations: no shared genre to name")
    }

    /// Unstarted books by none of the history's authors and in none of its series, those
    /// sharing its genres first, the rest shuffled so asking again gives other picks. Fewer
    /// than `atLeast` and the history's authors are let back in, after the others.
    static func differentShortlist(
        books: [AudiobookModel],
        collections: [CollectionModel],
        server: [AudiobookShelfAPI.Item],
        excluding excluded: Set<String>,
        atLeast: Int = 0
    ) -> [Candidate] {
        let history = history(books)
        let started = books.filter(isStarted)
        let authors = Set(history.compactMap { $0.author?.lowercased() })
        let titles = Set(started.compactMap { $0.title.map(normalizedTitle) })
        let genres = Set(history.flatMap { $0.hardcover?.genres ?? [] }.map { $0.lowercased() })
        let startedIDs = Set(started.map(\.id))
        let series = seriesCollections(collections)
        let listenedSeries = series.filter { $0.bookIDs.contains(where: startedIDs.contains) }.map { $0.name.lowercased() }
        let inSeries = Set(series.flatMap(\.bookIDs))

        let candidates = books.filter { !isStarted($0) && !inSeries.contains($0.id) }.map { Candidate($0) }
            + server.map(Candidate.init)
        let unstarted = candidates.filter { candidate in
            let series = candidate.series?.lowercased() ?? ""
            return !excluded.contains(candidate.id)
                && !titles.contains(normalizedTitle(candidate.title))
                && !listenedSeries.contains { !series.isEmpty && series.contains($0) }
        }
        func shared(_ candidate: Candidate) -> Int {
            candidate.genres.filter { genres.contains($0.lowercased()) }.count
        }
        func ranked(_ candidates: [Candidate]) -> [Candidate] { candidates.shuffled().sorted { shared($0) > shared($1) } }
        let byOthers = unstarted.filter { !authors.contains($0.author?.lowercased() ?? "") }
        let shortlist = byOthers.count >= atLeast
            ? ranked(byOthers)
            : ranked(byOthers) + ranked(unstarted.filter { authors.contains($0.author?.lowercased() ?? "") })
        return Array(shortlist.prefix(shortlistSize))
    }

    static func prompt(history: [AudiobookModel], shortlist: [Candidate]) -> String {
        let played = history.map { book in
            let state = book.isFinished
                ? "finished"
                : "\(Int(book.currentPosition / max(book.duration, 1) * 100))% listened"
            return "- \(book.title ?? "") by \(book.author ?? "unknown") (\(state))"
        }
        let options = shortlist.enumerated().map { index, candidate in
            var line = "\(index + 1). \(candidate.title) by \(candidate.author ?? "unknown")"
            if !candidate.genres.isEmpty { line += " [\(candidate.genres.joined(separator: ", "))]" }
            // Servers often keep the blurb as HTML.
            let blurb = candidate.blurb
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .prefix(160)
            if !blurb.isEmpty { line += ": \(blurb)" }
            return line
        }
        return """
            Books the listener played, most recent first:
            \(played.joined(separator: "\n"))

            Candidates:
            \(options.joined(separator: "\n"))
            """
    }
}

@Generable
struct GeneratedPicks {
    @Guide(description: "The three best candidates for this listener, best first", .count(3))
    var picks: [GeneratedPick]
}

@Generable
struct GeneratedPick {
    @Guide(description: "The candidate's number in the list")
    var number: Int
    @Guide(description: "One short sentence naming a book the listener played and what the two share")
    var reason: String
}
