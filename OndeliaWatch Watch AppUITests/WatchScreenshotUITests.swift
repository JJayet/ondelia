import XCTest

/// The watch screens the App Store listing shows, one attachment each. Driven by
/// `scripts/screenshots.sh`, which sets SCREENSHOT_LANGUAGE.
final class WatchScreenshotUITests: XCTestCase {
    private var app: XCUIApplication!

    @MainActor
    override func setUp() async throws {
        continueAfterFailure = false
        let language = ProcessInfo.processInfo.environment["SCREENSHOT_LANGUAGE"] ?? "en"
        app = XCUIApplication()
        app.launchArguments += [
            "--uitesting", "--seed-showcase",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", language == "fr" ? "fr_FR" : "en_US"
        ]
        app.launch()
    }

    @MainActor
    func testCaptureScreens() throws {
        let rows = app.cells
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "Seeded list should show. On screen:\n\(app.debugDescription)")
        snap("01-in-progress")

        // The row itself is the navigation link; its trailing button is the play/download action.
        rows.element(boundBy: 0).staticTexts.firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'play' OR label CONTAINS[c] 'lecture'")).firstMatch.waitForExistence(timeout: 5)
                      || app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        snap("02-player")

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        // The Chapters link sits below the three books; "Chap" covers Chapters and Chapitres.
        app.swipeUp()
        let chapters = app.cells.containing(NSPredicate(format: "label BEGINSWITH[c] 'Chap'")).firstMatch
        XCTAssertTrue(chapters.waitForExistence(timeout: 5), "Chapters link missing. On screen:\n\(app.debugDescription)")
        chapters.tap()
        snap("03-chapters")
    }

    @MainActor
    private func snap(_ name: String) {
        Thread.sleep(forTimeInterval: 1.5)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
