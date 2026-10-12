import XCTest

/// Back from a Collection, or from a book opened on one, returns to the screen it was opened
/// from. Both were state-driven destinations on the shelf, which SwiftUI stacked out of order.
@MainActor
final class CollectionNavigationUITests: AudiobookUITestCase {
    override var extraLaunchArguments: [String] { ["--reset-state", "--seed-series"] }

    private var seriesHeader: XCUIElement { app.staticTexts["SERIES"] }

    private func mistborn(in query: XCUIElementQuery) -> XCUIElement {
        query.matching(NSPredicate(format: "label CONTAINS 'Mistborn'")).firstMatch
    }

    func testBackFromCollectionReturnsToCollectionsScreen() throws {
        libraryTab.tap()
        let seeAll = app.buttons[AccessibilityIdentifiers.Library.seeAllCollections]
        XCTAssertTrue(seeAll.waitForExistence(timeout: 5), "--seed-series should make a Collection")
        seeAll.tap()
        XCTAssertTrue(app.navigationBars["Collections"].waitForExistence(timeout: 3))

        mistborn(in: app.buttons).tap()
        XCTAssertTrue(seriesHeader.waitForExistence(timeout: 3), "On screen instead:\n\(app.debugDescription)")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(
            app.navigationBars["Collections"].waitForExistence(timeout: 3),
            "Back should return to Collections. On screen instead:\n\(app.debugDescription)"
        )
    }

    func testBackFromBookReturnsToCollection() throws {
        libraryTab.tap()
        let tile = mistborn(in: app.scrollViews.buttons)
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "--seed-series should make a Collection")
        tile.tap()
        XCTAssertTrue(seriesHeader.waitForExistence(timeout: 3), "On screen instead:\n\(app.debugDescription)")

        app.buttons.matching(NSPredicate(format: "label CONTAINS 'The Well of Ascension'")).firstMatch.tap()
        XCTAssertTrue(app.buttons[AccessibilityIdentifiers.Library.resumeButton].waitForExistence(timeout: 3))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(
            seriesHeader.waitForExistence(timeout: 3),
            "Back should return to the Collection. On screen instead:\n\(app.debugDescription)"
        )
    }
}
