import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Publishes the library to Spotlight, so a book can be found and opened from search.
///
/// Items carry the audiobook's UUID as their identifier; `AudiobookReaderApp` turns a tapped
/// result back into a `audiobookreader://player` open.
enum SpotlightIndex {
    static let domain = "io.jayet.AudiobookReader.library"

    /// Replaces whatever was indexed. Cheap enough to run after a library fetch: Spotlight
    /// diffs the batch itself.
    ///
    /// The index objects are built inside the task rather than handed to it — none of
    /// CoreSpotlight's types are Sendable, so only the plain values cross.
    nonisolated static func reindex(_ books: [(id: UUID, title: String, author: String)]) {
        let entries = books.map { (id: $0.id.uuidString, title: $0.title, author: $0.author) }
        Task.detached(priority: .utility) {
            let index = CSSearchableIndex.default()
            let items = entries.map { entry -> CSSearchableItem in
                let attributes = CSSearchableItemAttributeSet(contentType: .audio)
                attributes.title = entry.title
                attributes.contentDescription = entry.author
                return CSSearchableItem(
                    uniqueIdentifier: entry.id,
                    domainIdentifier: domain,
                    attributeSet: attributes
                )
            }
            do {
                try await index.deleteSearchableItems(withDomainIdentifiers: [domain])
                try await index.indexSearchableItems(items)
            } catch {
                Log.library.error("❌ SpotlightIndex: \(error)")
            }
        }
    }
}
