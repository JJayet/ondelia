import Foundation
import Testing
@testable import Isora

@Suite("SpotlightIndex")
struct SpotlightIndexTests {
    private typealias Entry = SpotlightIndex.Entry

    @Test("Only new and changed books are reindexed, and only removed ones dropped")
    func diffSendsOnlyChanges() {
        let old = [
            "kept": Entry(title: "Dune", author: "Frank Herbert"),
            "renamed": Entry(title: "Old title", author: "Author"),
            "gone": Entry(title: "Deleted", author: "Author")
        ]
        let new = [
            "kept": Entry(title: "Dune", author: "Frank Herbert"),
            "renamed": Entry(title: "New title", author: "Author"),
            "added": Entry(title: "The Hobbit", author: "J.R.R. Tolkien")
        ]

        let diff = SpotlightIndex.diff(from: old, to: new)

        #expect(diff.changed == ["added", "renamed"])
        #expect(diff.removed == ["gone"])
    }

    @Test("An unchanged library sends nothing")
    func unchangedSendsNothing() {
        let entries = ["a": Entry(title: "Dune", author: "Frank Herbert")]
        let diff = SpotlightIndex.diff(from: entries, to: entries)

        #expect(diff.changed.isEmpty)
        #expect(diff.removed.isEmpty)
    }
}
