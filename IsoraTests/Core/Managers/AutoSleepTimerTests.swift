//
//  AutoSleepTimerTests.swift
//  IsoraTests
//

import Testing
import Foundation
@testable import Isora

@MainActor
@Suite("Automatic sleep timer", .serialized, .tags(.manager))
struct AutoSleepTimerTests {
    private let defaults = UserDefaults.standard
    private let manager = GlobalAudioManager.shared

    private func reset() {
        manager.cancelSleepTimer()
        defaults.removeObject(forKey: GlobalAudioManager.autoSleepTimerKey)
        defaults.removeObject(forKey: GlobalAudioManager.lastSleepTimerSecondsKey)
        defaults.removeObject(forKey: GlobalAudioManager.lastSleepTimerEndOfChapterKey)
    }

    @Test("Off: play starts no timer")
    func disabled() {
        reset()
        manager.startAutomaticSleepTimerIfEnabled()
        #expect(manager.sleepTimeRemaining == 0)
        reset()
    }

    @Test("On: play repeats the last chosen duration, and never restarts a running one")
    func repeatsLastDuration() {
        reset()
        manager.setSleepTimer(600)
        manager.cancelSleepTimer()
        defaults.set(true, forKey: GlobalAudioManager.autoSleepTimerKey)

        manager.startAutomaticSleepTimerIfEnabled()
        #expect(manager.sleepTimeRemaining == 600)

        manager.setSleepTimer(300)
        manager.startAutomaticSleepTimerIfEnabled()
        #expect(manager.sleepTimeRemaining == 300)
        reset()
    }

    @Test("On with nothing chosen yet: 15 minutes")
    func defaultDuration() {
        reset()
        defaults.set(true, forKey: GlobalAudioManager.autoSleepTimerKey)
        manager.startAutomaticSleepTimerIfEnabled()
        #expect(manager.sleepTimeRemaining == 900)
        reset()
    }
}
