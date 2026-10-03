//
//  AudiobookUITestCase.swift
//  IsoraUITests
//

import XCTest

/// One launch path for every UI suite.
///
/// Each suite used to build its own `XCUIApplication` and look the Library tab up by
/// accessibility identifier. SwiftUI's `Tab` puts no identifier on the tab bar button — whether
/// it is set on the `Tab` or inside its `Label`, the button surfaces only its localized label —
/// so every suite failed at setup before touching the app. The lookup is by label here, with
/// the language pinned so the label is known rather than the simulator's.
@MainActor
class AudiobookUITestCase: XCTestCase {
    var app: XCUIApplication!

    /// Launch arguments a suite needs on top of the shared ones.
    var extraLaunchArguments: [String] { [] }

    /// Language the app runs in. Fixed so tab labels are known, overridable for screenshots.
    var language: String { "en" }

    // iPad exposes the identifiers (buttons in the top strip, cells in the landscape sidebar);
    // iPhone's tab bar exposes only localized labels, so there the lookup falls back to position.
    var libraryTab: XCUIElement { tab(AccessibilityIdentifiers.TabBar.libraryTab, index: 0) }
    var statisticsTab: XCUIElement { tab("tab_bar_statistics", index: 1) }
    var settingsTab: XCUIElement { tab(AccessibilityIdentifiers.TabBar.settingsTab, index: 2) }

    private func tab(_ identifier: String, index: Int) -> XCUIElement {
        let byIdentifier = app.descendants(matching: .any)[identifier].firstMatch
        return byIdentifier.exists ? byIdentifier : app.tabBars.buttons.element(boundBy: index)
    }

    /// The library rows. The identifier sits on each row's button, not on the collection view
    /// cell SwiftUI wraps it in.
    var audiobookRows: XCUIElementQuery {
        app.buttons.matching(identifier: AccessibilityIdentifiers.Library.audiobookCell)
    }

    /// Taps Resume on the book detail screen a library row opens, landing in the player.
    @discardableResult
    func openPlayerFromDetail(timeout: TimeInterval = 5) -> Bool {
        let resumeButton = app.buttons[AccessibilityIdentifiers.Library.resumeButton]
        guard resumeButton.waitForExistence(timeout: timeout) else { return false }
        resumeButton.tap()
        return playPauseButton.waitForExistence(timeout: timeout)
    }

    /// The player's play/pause. In regular width the player is the Now Playing pane and its
    /// transport is the tab accessory bar, which carries the mini player's identifier.
    var playPauseButton: XCUIElement {
        let full = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
        return full.exists ? full : app.buttons[AccessibilityIdentifiers.MiniPlayer.playPauseButton]
    }

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "--uitesting",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", language == "fr" ? "fr_FR" : "en_US",
            // The device shelf, whatever the simulator remembers: a signed-in AudiobookShelf
            // server left the Library on the server's shelf, so no suite found its seeded book.
            "-library.source", "device",
            "-audiobookshelf.showInLibrary", "NO"
        ] + extraLaunchArguments
        app.launch()

        // The tree in the message: a bare "did not launch" says nothing about which screen the
        // app actually stopped on, and that was the whole cost of diagnosing these suites.
        XCTAssertTrue(
            libraryTab.waitForExistence(timeout: 10),
            "App should launch to the library tab. On screen instead:\n\(app.debugDescription)"
        )
    }

    /// Relaunches the app under test with extra arguments.
    ///
    /// The suites used to build a second `XCUIApplication`, launch that, and then assert against
    /// `app` — which they had just terminated. Everything after the relaunch failed on an app
    /// that was not running.
    func relaunch(with extraArguments: [String]) {
        app.terminate()
        app.launchArguments += extraArguments
        app.launch()
        XCTAssertTrue(
            libraryTab.waitForExistence(timeout: 10),
            "App should relaunch to the library tab"
        )
    }

    override func tearDown() async throws {
        app.terminate()
        app = nil
    }

    /// Opens the seeded book's player. `--uitesting` seeds one book, so a missing row is a
    /// failure rather than a reason to skip: skipping passed these suites while nothing at all
    /// was being exercised.
    func navigateToPlayer() throws {
        libraryTab.tap()

        let firstAudiobook = audiobookRows.firstMatch
        XCTAssertTrue(
            firstAudiobook.waitForExistence(timeout: 5),
            "UITestBootstrap should have seeded an audiobook"
        )
        firstAudiobook.tap()

        // A library row opens the book's detail screen; the player is one tap further in.
        let resumeButton = app.buttons[AccessibilityIdentifiers.Library.resumeButton]
        XCTAssertTrue(
            resumeButton.waitForExistence(timeout: 5),
            "Tapping an audiobook should open its detail screen. On screen instead:\n\(app.debugDescription)"
        )
        resumeButton.tap()

        XCTAssertTrue(
            playPauseButton.waitForExistence(timeout: 5),
            "Player should load after tapping an audiobook"
        )
    }
}
