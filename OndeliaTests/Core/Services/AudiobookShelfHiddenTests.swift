import Testing
import Foundation
@testable import Isora

@Suite("AudiobookShelf hidden entries")
@MainActor
struct AudiobookShelfHiddenTests {
    @Test("A book is hidden on its own or by any of its authors, on its own server only")
    func bookHiddenByItselfOrAuthor() {
        let hidden = AudiobookShelfHidden()
        hidden.apply([
            HiddenServerEntryModel(serverID: "s1", kind: .book, entityID: "li_a", name: "Dune"),
            HiddenServerEntryModel(serverID: "s1", kind: .author, entityID: "au_1", name: "Ursula K. Le Guin"),
            HiddenServerEntryModel(serverID: "s1", kind: .series, entityID: "se_1", name: "Earthsea")
        ])
        #expect(hidden.isHidden(item: "li_a", authors: "Frank Herbert", on: "s1"))
        #expect(!hidden.isHidden(item: "li_a", authors: "Frank Herbert", on: "s2"))
        #expect(hidden.isHidden(item: "li_b", authors: "Someone, ursula k. le guin", on: "s1"))
        #expect(!hidden.isHidden(item: "li_b", authors: "Frank Herbert", on: "s1"))
        #expect(hidden.hidingAuthor(of: "Someone, Ursula K. Le Guin", on: "s1") == "Ursula K. Le Guin")
        // A hidden series hides the series, not its books.
        #expect(hidden.isHidden(.series, "se_1", on: "s1"))
        #expect(!hidden.isHidden(item: "li_c", authors: nil, on: "s1"))
    }
}
