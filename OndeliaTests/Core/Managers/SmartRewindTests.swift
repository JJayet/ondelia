//
//  SmartRewindTests.swift
//  IsoraTests
//

import Testing
import Foundation
@testable import Isora

@MainActor
@Suite("Smart Rewind", .tags(.manager))
struct SmartRewindTests {
    /// A chapter long enough that the chapter-start clamp never bites.
    private let deepInChapter: TimeInterval = 10_000

    @Test("A short pause rewinds the floor, not less")
    func shortPause() {
        let rewind = GlobalAudioManager.smartRewindAmount(away: 10, timeInChapter: deepInChapter)
        #expect(rewind == GlobalAudioManager.smartRewindMinimum)
    }

    @Test("The rewind grows with the pause and stops at the maximum")
    func growsThenPlateaus() {
        let short = GlobalAudioManager.smartRewindAmount(away: 60, timeInChapter: deepInChapter)
        let medium = GlobalAudioManager.smartRewindAmount(away: 15 * 60, timeInChapter: deepInChapter)
        let long = GlobalAudioManager.smartRewindAmount(away: 60 * 60, timeInChapter: deepInChapter)
        let overnight = GlobalAudioManager.smartRewindAmount(away: 8 * 60 * 60, timeInChapter: deepInChapter)

        #expect(short < medium)
        #expect(medium < long)
        #expect(long == GlobalAudioManager.smartRewindMaxInterval)
        // Past the threshold every pause is the same pause.
        #expect(overnight == long)
    }

    @Test("Never rewinds further than the pause lasted")
    func clampedToPause() {
        #expect(GlobalAudioManager.smartRewindAmount(away: 0.5, timeInChapter: deepInChapter) == 0.5)
    }

    @Test("Never rewinds past the start of the chapter")
    func clampedToChapter() {
        #expect(GlobalAudioManager.smartRewindAmount(away: 60 * 60, timeInChapter: 4) == 4)
        #expect(GlobalAudioManager.smartRewindAmount(away: 60 * 60, timeInChapter: 0) == 0)
    }

    @Test("A clock that moved backwards rewinds nothing")
    func negativePause() {
        #expect(GlobalAudioManager.smartRewindAmount(away: -100, timeInChapter: deepInChapter) == 0)
    }

    @Test("Non-finite input is ignored rather than seeked to")
    func nonFinite() {
        #expect(GlobalAudioManager.smartRewindAmount(away: .nan, timeInChapter: deepInChapter) == 0)
        #expect(GlobalAudioManager.smartRewindAmount(away: 60, timeInChapter: .infinity) == 0)
    }
}
