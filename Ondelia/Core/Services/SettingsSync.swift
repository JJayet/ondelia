import Foundation
import UIKit

/// Mirrors the preferences between `UserDefaults` and iCloud's key-value store, so a second
/// device starts with the settings of the first instead of the defaults. Last write wins.
/// Follows the iCloud sync toggle; a change to the toggle applies at the next launch.
@MainActor
enum SettingsSync {
    /// Same value on every device.
    static let sharedKeys = [
        "selectedTheme", "accentColor",
        "skipBackInterval", "skipForwardInterval",
        "globalSpeedEnabled", "globalSpeed", "smartRewindEnabled",
        "playback.autoSleepTimer", "playback.deleteOnCompletion", "playback.bookOpeningDelayMS",
        "library.autoSeriesCollections", "library.showMissingSeriesBooks",
        "library.viewMode", "library.sortOption", "library.filterOption",
        "player.showChapterTimes", "player.scrubsBook",
        // Only written once the listener sets it, so a device on the default never overwrites it.
        "monthlyGoal",
        // The AudiobookShelf token itself goes through iCloud Keychain, never through here.
        AudiobookShelfService.Defaults.server, AudiobookShelfService.Defaults.username,
        AudiobookShelfService.Defaults.library, AudiobookShelfCatalog.enabledKey
    ]

    /// One value per device family: the grid density that suits a phone is wrong on a Mac.
    static let perDeviceFamilyKeys = ["library.gridColumns"]

    /// "phone", "pad" or "mac" — the suffix a per-family key carries in iCloud.
    static var deviceFamily: String {
        if ProcessInfo.processInfo.isiOSAppOnMac { return "mac" }
        return UIDevice.current.userInterfaceIdiom == .phone ? "phone" : "pad"
    }

    /// (local key, cloud key) for everything mirrored.
    static var keyPairs: [(local: String, cloud: String)] {
        sharedKeys.map { ($0, $0) } + perDeviceFamilyKeys.map { ($0, "\($0).\(deviceFamily)") }
    }

    private static var observers: [NSObjectProtocol] = []

    static func start() {
        guard SwiftDataController.isICloudSyncEnabled,
              !ProcessInfo.processInfo.arguments.contains("--uitesting") else { return }
        let cloud = NSUbiquitousKeyValueStore.default
        observers = [
            NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: cloud,
                queue: .main
            ) { _ in MainActor.assumeIsolated { pull() } },
            NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: UserDefaults.standard,
                queue: .main
            ) { _ in MainActor.assumeIsolated { push() } }
        ]
        cloud.synchronize()
        pull()
    }

    /// iCloud → defaults. Writing a value defaults already hold posts a change, and `push`
    /// then finds nothing different, so the two never echo.
    static func pull() {
        let cloud = NSUbiquitousKeyValueStore.default
        let defaults = UserDefaults.standard
        var changed = false
        for pair in keyPairs {
            guard let remote = cloud.object(forKey: pair.cloud), !equal(remote, defaults.object(forKey: pair.local)) else { continue }
            defaults.set(remote, forKey: pair.local)
            changed = true
        }
        if changed {
            ThemeManager.shared.loadSettings()
            ReadingStatistics.shared.loadMonthlyGoal()
        }
    }

    /// Defaults → iCloud, only the keys whose value differs.
    static func push() {
        let cloud = NSUbiquitousKeyValueStore.default
        let defaults = UserDefaults.standard
        for pair in keyPairs {
            guard let local = defaults.object(forKey: pair.local), !equal(local, cloud.object(forKey: pair.cloud)) else { continue }
            cloud.set(local, forKey: pair.cloud)
        }
    }

    private static func equal(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (let a as NSObject, let b as NSObject): return a.isEqual(b)
        default: return false
        }
    }
}
