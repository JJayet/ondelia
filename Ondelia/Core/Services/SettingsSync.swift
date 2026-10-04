import Foundation
import UIKit

/// What `SettingsSync` needs from either side; both stores already answer it.
protocol SettingsStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

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
        // The AudiobookShelf token itself goes through iCloud Keychain, never through here.
        AudiobookShelfService.accountsKey,
        AudiobookShelfService.Defaults.server, AudiobookShelfService.Defaults.username,
        AudiobookShelfService.Defaults.library, AudiobookShelfCatalog.enabledKey,
        AudiobookShelfService.Defaults.tapAction
    ]

    /// Set by the listener and never pushed on their own: `publish` sends the listener's change,
    /// and a device seeds the cloud from its own value only after hearing that the cloud has none,
    /// so a stale or default value never overwrites one set elsewhere.
    static let listenerSetKeys = [ReadingStatistics.Defaults.monthlyGoal]

    /// String sets merged as a union both ways, so nothing added on one device is ever dropped.
    static let unionKeys = [ReadingStatistics.Defaults.shownMilestones]

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
            ) { _ in MainActor.assumeIsolated { pull(seed: true) } },
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
    /// then finds nothing different, so the two never echo. `seed` is set once the cloud has
    /// spoken, when a listener-set key it lacks is known to be absent rather than not downloaded.
    static func pull(
        cloud: SettingsStore = NSUbiquitousKeyValueStore.default,
        defaults: UserDefaults = .standard,
        seed: Bool = false
    ) {
        var changed = false
        let pairs = keyPairs + listenerSetKeys.map { ($0, $0) }
        for pair in pairs {
            guard let remote = cloud.object(forKey: pair.cloud), !equal(remote, defaults.object(forKey: pair.local)) else { continue }
            defaults.set(remote, forKey: pair.local)
            changed = true
        }
        for key in listenerSetKeys where seed && cloud.object(forKey: key) == nil {
            if let local = defaults.object(forKey: key) { cloud.set(local, forKey: key) }
        }
        for key in unionKeys {
            let local = defaults.stringArray(forKey: key) ?? []
            let merged = union(local, cloud.object(forKey: key))
            if merged.count > local.count { defaults.set(merged, forKey: key) }
        }
        if changed {
            ThemeManager.shared.loadSettings()
            ReadingStatistics.shared.loadMonthlyGoal(from: defaults)
        }
    }

    /// Defaults → iCloud, only the keys whose value differs. Listener-set keys go through `publish`.
    static func push(cloud: SettingsStore = NSUbiquitousKeyValueStore.default, defaults: UserDefaults = .standard) {
        for pair in keyPairs {
            guard let local = defaults.object(forKey: pair.local), !equal(local, cloud.object(forKey: pair.cloud)) else { continue }
            cloud.set(local, forKey: pair.cloud)
        }
        for key in unionKeys {
            let remote = cloud.object(forKey: key) as? [String] ?? []
            let merged = union(remote, defaults.object(forKey: key))
            if merged.count > remote.count { cloud.set(merged, forKey: key) }
        }
    }

    /// The listener just changed `key` here: overwrites the cloud's value. A no-op with sync off.
    static func publish(_ key: String) {
        guard !observers.isEmpty else { return }
        NSUbiquitousKeyValueStore.default.set(UserDefaults.standard.object(forKey: key), forKey: key)
    }

    /// `base` plus whatever strings `other` holds that it lacks, in a stable order.
    private static func union(_ base: [String], _ other: Any?) -> [String] {
        let extra = (other as? [String] ?? []).filter { !base.contains($0) }
        return base + Set(extra).sorted()
    }

    private static func equal(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (let a as NSObject, let b as NSObject): return a.isEqual(b)
        default: return false
        }
    }
}

extension NSUbiquitousKeyValueStore: SettingsStore {}
extension UserDefaults: SettingsStore {}
