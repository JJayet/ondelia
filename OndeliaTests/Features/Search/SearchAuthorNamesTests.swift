import Testing
@testable import Isora

@MainActor
@Suite("Search author names")
struct SearchAuthorNamesTests {
    @Test("A shared credit splits into one name per author")
    func splitsSharedCredits() {
        #expect(SearchView.authorNames("Peter Straub, Stephen King") == ["Peter Straub", "Stephen King"])
        #expect(SearchView.authorNames("Neil Gaiman & Terry Pratchett") == ["Neil Gaiman", "Terry Pratchett"])
        #expect(SearchView.authorNames("Stephen King") == ["Stephen King"])
        #expect(SearchView.authorNames("").isEmpty)
    }
}
