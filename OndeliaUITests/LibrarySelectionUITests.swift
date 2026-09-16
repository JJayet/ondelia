import XCTest

/// Selection mode: tapping a row's mark toggles it, and an emptied shelf leaves the mode.
@MainActor
final class LibrarySelectionUITests: AudiobookUITestCase {
    override var extraLaunchArguments: [String] { ["--reset-state"] }

    func testMarkTapSelectsAndEmptyShelfEndsSelecting() throws {
        let row = audiobookRows.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "UITestBootstrap should have seeded an audiobook")

        app.buttons["Select"].tap()
        // The mark sits at the trailing edge, where the chevron was.
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(
            app.buttons["1 selected"].waitForExistence(timeout: 3),
            "Tapping the mark should select the row. On screen instead:\n\(app.debugDescription)"
        )

        row.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        app.alerts.buttons["Delete"].tap()

        XCTAssertTrue(
            app.buttons["Select"].waitForExistence(timeout: 3),
            "Deleting the last book should leave selection mode. On screen instead:\n\(app.debugDescription)"
        )
    }
}
