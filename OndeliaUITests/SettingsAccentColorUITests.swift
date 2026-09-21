import XCTest

@MainActor
final class SettingsAccentColorUITests: XCTestCase {
    func testSettingsColorMenuCanOpenAndSelectColor() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        let menu = app.buttons["Accent Color"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        let originalColor = menu.value as? String
        menu.tap()
        let blue = app.buttons["Blue"].firstMatch
        XCTAssertTrue(blue.waitForExistence(timeout: 5))
        blue.tap()
        XCTAssertEqual(menu.value as? String, "Blue")
        if let originalColor, originalColor != "Blue" {
            menu.tap()
            app.buttons[originalColor].firstMatch.tap()
            XCTAssertEqual(menu.value as? String, originalColor)
        }
        XCTAssertEqual(app.state, .runningForeground)
    }
}
