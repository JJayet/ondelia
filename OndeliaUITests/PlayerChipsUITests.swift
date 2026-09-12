import XCTest

/// The player chips each open a sheet; a modifier added to the chip row (a tip anchor, say)
/// must not swallow the tap.
final class PlayerChipsUITests: AudiobookUITestCase {
    func testTranscriptChipOpensSheet() throws {
        try navigateToPlayer()
        let chip = app.buttons["Transcript"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5), app.debugDescription)
        chip.tap()
        XCTAssertTrue(
            app.navigationBars.firstMatch.waitForExistence(timeout: 5),
            "Transcript sheet did not open. On screen:\n\(app.debugDescription)"
        )
    }

    func testBookmarksChipOpensSheet() throws {
        try navigateToPlayer()
        let chip = app.buttons[AccessibilityIdentifiers.Player.bookmarksButton]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()
        XCTAssertTrue(
            app.buttons["bookmarks_add_button"].waitForExistence(timeout: 5),
            "Bookmarks sheet did not open. On screen:\n\(app.debugDescription)"
        )
    }
}
