import Foundation
import Observation

/// Pages of one server list, loaded as the shelf scrolls to their end.
///
/// Books, series and authors all page the same way; only the request differs. A list the
/// server returns in one piece is a single page whose count is its total.
@MainActor
@Observable
final class AudiobookShelfPager<Element: Identifiable> {
    typealias Fetch = (_ page: Int) async throws -> (items: [Element], total: Int)

    private(set) var items: [Element] = []
    private(set) var isLoading = false
    private(set) var error: String?
    /// Nil until the first page has answered.
    private(set) var total: Int?
    private var nextPage = 0
    private let fetch: Fetch

    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    var isExhausted: Bool { total.map { items.count >= $0 } ?? false }

    /// Loads the next page when `item` is the last one shown, or the first page when nothing
    /// is shown yet.
    func loadMore(after item: Element? = nil) async {
        guard !isLoading, !isExhausted else { return }
        if let item, item.id != items.last?.id { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await fetch(nextPage)
            items += page.items
            total = page.total
            nextPage += 1
            error = nil
            // A server that ignores the limit, or a page shorter than promised: stop here
            // rather than asking for an empty page forever.
            if page.items.isEmpty { total = items.count }
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}
