import XCTest

/// Exercises the first-launch layout without clearing the user's library or changing settings.
@MainActor
final class OnboardingLayoutUITests: XCTestCase {
    func testFrenchOptionsRemainReachableAfterRotationRequests() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed", "NO", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]
        app.launch()
        defer { XCUIDevice.shared.orientation = .portrait }

        let next = app.buttons["Continuer"]
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        next.tap()
        next.tap()

        // Rotation requests do not unfold Duo; exercise unfolding separately in Simulator.
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(app.staticTexts["À votre image"].waitForExistence(timeout: 5))
            capture(app, name: "Appearance-\(orientation.rawValue)")
            XCTAssertTrue(next.isHittable)
        }

        next.tap()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let scroll = app.scrollViews.firstMatch
            scroll.swipeDown()
            capture(app, name: "Playback-top-\(orientation.rawValue)")
            let lastOption = app.switches["Supprimer le livre une fois terminé"]
            for _ in 0..<4 {
                if lastOption.isHittable && lastOption.frame.maxY < app.pageIndicators.firstMatch.frame.minY { break }
                scroll.swipeUp()
            }
            XCTAssertTrue(lastOption.isHittable, "The final setting must remain reachable by scrolling.")
            XCTAssertLessThan(lastOption.frame.maxY, app.pageIndicators.firstMatch.frame.minY,
                              "Pagination must have its own space below the settings.")
            XCTAssertTrue(next.isHittable)
            capture(app, name: "Playback-bottom-\(orientation.rawValue)")
        }
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
