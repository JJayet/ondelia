import XCTest

/// Walks the screens the App Store listing shows and attaches one screenshot per screen.
/// Not a test of anything; `scripts/screenshots.sh` runs it per device and language and
/// exports the attachments.
final class ScreenshotUITests: AudiobookUITestCase {
    override var language: String { ProcessInfo.processInfo.environment["SCREENSHOT_LANGUAGE"] ?? "en" }
    override var extraLaunchArguments: [String] {
        // iCloud off: the store must be local so the seed is what the screen shows.
        var arguments = ["--reset-state", "--seed-showcase", "-sync.iCloud", "NO"]
        if ProcessInfo.processInfo.environment["SCREENSHOT_DARK"] == "1" { arguments += ["-selectedTheme", "2"] }
        return arguments
    }

    /// App Store iPad shots are landscape: the sidebar layout is the point of the pane.
    override func setUp() async throws {
        if UIDevice.current.userInterfaceIdiom == .pad { XCUIDevice.shared.orientation = .landscapeLeft }
        try await super.setUp()
    }

    func testCaptureScreens() throws {
        libraryTab.tap()
        XCTAssertTrue(audiobookRows.firstMatch.waitForExistence(timeout: 10))
        snap("01-library")

        audiobookRows.firstMatch.tap()
        XCTAssertTrue(app.buttons[AccessibilityIdentifiers.Library.resumeButton].waitForExistence(timeout: 5))
        snap("02-book-detail")

        XCTAssertTrue(openPlayerFromDetail())
        snap("03-player")

        // Regular width lists the chapters in the player itself and has no close button:
        // the player is the Now Playing pane, and the sidebar tabs stay reachable.
        let chaptersButton = app.buttons[AccessibilityIdentifiers.Player.chaptersButton]
        if chaptersButton.exists {
            chaptersButton.tap()
            snap("04-chapters")
            // The sheet's Done is its only bar button, whatever the language calls it.
            app.navigationBars.buttons.firstMatch.tap()
            app.buttons[AccessibilityIdentifiers.Player.closeButton].tap()
        }
        XCTAssertTrue(statisticsTab.waitForExistence(timeout: 5))

        statisticsTab.tap()
        snap("05-statistics")

        settingsTab.tap()
        snap("06-settings")
    }

    private func snap(_ name: String) {
        // Let transitions settle; a mid-animation frame is not a screenshot.
        Thread.sleep(forTimeInterval: 1.5)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
