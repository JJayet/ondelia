import Foundation
import Observation
import SwiftData

/// What the listener hid from each server: `HiddenServerEntryModel` records, held in memory so
/// the Library, Search and Collections can filter on every redraw.
///
/// Hiding a series or collection hides that entry only. Hiding an author hides the author and
/// every book of theirs; books carry author names, not ids, so they match by name.
@MainActor
@Observable
final class AudiobookShelfHidden {
    static let shared = AudiobookShelfHidden()

    struct Key: Hashable {
        let serverID: String
        let kind: HiddenServerEntryModel.Kind
        let entityID: String
    }

    struct Entry: Hashable, Identifiable {
        let key: Key
        let name: String
        var id: Key { key }
    }

    private(set) var entries: [Key: Entry] = [:]
    /// Hidden authors' names by server, folded for matching.
    private(set) var authorNames: [String: Set<String>] = [:]

    /// Rereads the records: at launch, after each library fetch, and after another device's
    /// changes arrive.
    func reload() {
        guard SwiftDataController.shared.isLoaded else { return }
        apply((try? SwiftDataController.shared.context.fetch(FetchDescriptor<HiddenServerEntryModel>())) ?? [])
    }

    func apply(_ records: [HiddenServerEntryModel]) {
        var next: [Key: Entry] = [:]
        for record in records {
            guard let kind = HiddenServerEntryModel.Kind(rawValue: record.kind) else { continue }
            let key = Key(serverID: record.serverID, kind: kind, entityID: record.entityID)
            next[key] = Entry(key: key, name: record.name)
        }
        guard next != entries else { return }
        entries = next
        authorNames = Dictionary(grouping: next.values.filter { $0.key.kind == .author }, by: \.key.serverID)
            .mapValues { Set($0.map { Self.fold($0.name) }) }
    }

    func isHidden(_ kind: HiddenServerEntryModel.Kind, _ entityID: String, on serverID: String?) -> Bool {
        guard let serverID else { return false }
        return entries[Key(serverID: serverID, kind: kind, entityID: entityID)] != nil
    }

    /// A book is hidden when it is, or when one of its authors is.
    func isHidden(item: String, authors: String?, on serverID: String?) -> Bool {
        guard let serverID, !entries.isEmpty else { return false }
        if isHidden(.book, item, on: serverID) { return true }
        guard let hidden = authorNames[serverID], let authors else { return false }
        return Self.names(in: authors).contains { hidden.contains($0) }
    }

    func isHidden(_ item: AudiobookShelfAPI.Item, on serverID: String?) -> Bool {
        isHidden(item: item.id, authors: item.author, on: serverID)
    }

    /// Hidden by one of its authors rather than on its own: showing it again means showing them.
    func hidingAuthor(of authors: String?, on serverID: String) -> String? {
        guard let hidden = authorNames[serverID], let authors else { return nil }
        return authors.components(separatedBy: ", ").first { hidden.contains(Self.fold($0)) }
    }

    func filter(_ results: AudiobookShelfAPI.SearchResults, on serverID: String?) -> AudiobookShelfAPI.SearchResults {
        guard !entries.isEmpty else { return results }
        var kept = results
        kept.books.removeAll { isHidden($0, on: serverID) }
        kept.series.removeAll { isHidden(.series, $0.id, on: serverID) }
        kept.authors.removeAll { isHidden(.author, $0.id, on: serverID) }
        return kept
    }

    func hide(_ kind: HiddenServerEntryModel.Kind, _ entityID: String, name: String, on serverID: String) {
        guard !isHidden(kind, entityID, on: serverID) else { return }
        SwiftDataController.shared.context.insert(
            HiddenServerEntryModel(serverID: serverID, kind: kind, entityID: entityID, name: name)
        )
        SwiftDataController.shared.save()
        reload()
    }

    /// Deletes every match: two devices may each have hidden it.
    func show(_ kind: HiddenServerEntryModel.Kind, _ entityID: String, on serverID: String) {
        let raw = kind.rawValue
        let context = SwiftDataController.shared.context
        let matches = (try? context.fetch(FetchDescriptor<HiddenServerEntryModel>(predicate: #Predicate {
            $0.serverID == serverID && $0.kind == raw && $0.entityID == entityID
        }))) ?? []
        for record in matches { context.delete(record) }
        SwiftDataController.shared.save()
        reload()
    }

    func hidden(_ kind: HiddenServerEntryModel.Kind, on serverID: String) -> [Entry] {
        entries.values
            .filter { $0.key.serverID == serverID && $0.key.kind == kind }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// "Name, Other" as AudiobookShelf lists authors, folded.
    nonisolated static func names(in authors: String) -> [String] {
        authors.components(separatedBy: ", ").map(fold)
    }

    nonisolated static func fold(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
