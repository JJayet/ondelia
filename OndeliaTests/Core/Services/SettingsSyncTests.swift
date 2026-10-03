//
//  SettingsSyncTests.swift
//  IsoraTests
//

import Testing
import Foundation
@testable import Isora

@MainActor
@Suite("Settings sync")
struct SettingsSyncTests {
    /// Two throwaway suites standing in for iCloud and this device's defaults.
    let cloud = UserDefaults(suiteName: "SettingsSyncTests.cloud.\(UUID().uuidString)") ?? .standard
    let defaults = UserDefaults(suiteName: "SettingsSyncTests.local.\(UUID().uuidString)") ?? .standard
    let goal = ReadingStatistics.Defaults.monthlyGoal
    let earned = ReadingStatistics.Defaults.shownMilestones

    @Test("A device on the default goal never pushes one")
    func defaultNeverPushed() {
        SettingsSync.push(cloud: cloud, defaults: defaults)
        SettingsSync.pull(cloud: cloud, defaults: defaults, seed: true)
        #expect(cloud.object(forKey: goal) == nil)
    }

    @Test("A goal set on this device is not pushed by a settings change")
    func localGoalNotPushed() {
        defaults.set(20.0 * 3600, forKey: goal)
        SettingsSync.push(cloud: cloud, defaults: defaults)
        #expect(cloud.object(forKey: goal) == nil)
    }

    @Test("Once the cloud is heard from and has no goal, this device's goal seeds it")
    func seedsWhenCloudEmpty() {
        defaults.set(20.0 * 3600, forKey: goal)
        SettingsSync.pull(cloud: cloud, defaults: defaults)
        #expect(cloud.object(forKey: goal) == nil)
        SettingsSync.pull(cloud: cloud, defaults: defaults, seed: true)
        #expect(cloud.double(forKey: goal) == 20 * 3600)
    }

    @Test("The synced goal wins over a stale one on this device")
    func cloudWinsOverStaleLocal() {
        cloud.set(30.0 * 3600, forKey: goal)
        defaults.set(5.0 * 3600, forKey: goal)
        SettingsSync.push(cloud: cloud, defaults: defaults)
        SettingsSync.pull(cloud: cloud, defaults: defaults, seed: true)
        #expect(cloud.double(forKey: goal) == 30 * 3600)
        #expect(defaults.double(forKey: goal) == 30 * 3600)
    }

    @Test("Pulling a goal reloads the statistics' goal")
    func pullReloadsStatistics() {
        cloud.set(42.0 * 3600, forKey: goal)
        SettingsSync.pull(cloud: cloud, defaults: defaults)
        #expect(ReadingStatistics.shared.monthlyGoal == 42 * 3600)
        ReadingStatistics.shared.loadMonthlyGoal()
    }

    @Test("Earned milestones merge as a union and are never dropped")
    func milestonesUnion() {
        cloud.set(["hours10", "earlyBird"], forKey: earned)
        defaults.set(["earlyBird", "nightOwl"], forKey: earned)
        SettingsSync.pull(cloud: cloud, defaults: defaults)
        SettingsSync.push(cloud: cloud, defaults: defaults)
        let expected: Set = ["hours10", "earlyBird", "nightOwl"]
        #expect(Set(defaults.stringArray(forKey: earned) ?? []) == expected)
        #expect(Set(cloud.stringArray(forKey: earned) ?? []) == expected)

        // An emptier list on either side takes nothing away.
        defaults.set([String](), forKey: earned)
        SettingsSync.push(cloud: cloud, defaults: defaults)
        SettingsSync.pull(cloud: cloud, defaults: defaults)
        #expect(Set(cloud.stringArray(forKey: earned) ?? []) == expected)
        #expect(Set(defaults.stringArray(forKey: earned) ?? []) == expected)
    }
}
