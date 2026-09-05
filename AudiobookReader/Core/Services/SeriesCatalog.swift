import Foundation

/// One volume of a series as Hardcover lists it — owned or not.
struct SeriesVolume: Codable, Hashable, Identifiable, Sendable {
    let bookID: Int
    let title: String
    let position: Double?

    var id: Int { bookID }

    /// "#2", or nil for a volume whose place Hardcover does not record.
    var badge: String? {
        HardcoverLink(id: bookID, title: title, author: "", seriesPosition: position).volumeBadge
    }
}

/// What Hardcover says a series contains, kept between launches.
///
/// In `UserDefaults` rather than SwiftData: it is a cache of someone else's catalogue, a few
/// dozen short rows per series, and losing it costs one request.
@MainActor
enum SeriesCatalog {
    private static let prefix = "hardcover.series.v2."

    static func volumes(for seriesID: Int) -> [SeriesVolume] {
        guard let data = UserDefaults.standard.data(forKey: prefix + String(seriesID)) else { return [] }
        return (try? JSONDecoder().decode([SeriesVolume].self, from: data)) ?? []
    }

    static func store(_ volumes: [SeriesVolume], for seriesID: Int) {
        guard let data = try? JSONEncoder().encode(volumes) else { return }
        UserDefaults.standard.set(data, forKey: prefix + String(seriesID))
    }
}
