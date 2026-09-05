//
//  HardcoverProgressTests.swift
//  IsoraTests
//

import Testing
import Foundation
@testable import Isora

@Suite("Hardcover progress")
struct HardcoverProgressTests {
    private func edition(_ id: Int, _ seconds: Int) -> HardcoverAPI.AudioEdition {
        HardcoverAPI.AudioEdition(id: id, audioSeconds: seconds)
    }

    @Test("Picks the edition whose length matches the file")
    func picksClosest() {
        let editions = [edition(1, 3600), edition(2, 43_200), edition(3, 21_600)]
        // A twelve-hour book: the abridged and the popular short edition are both wrong.
        #expect(HardcoverAPI.closestEdition(editions, to: 43_100)?.id == 2)
    }

    @Test("Falls back to the most popular edition with no duration to compare")
    func fallsBackToFirst() {
        // Editions arrive most-listened first.
        let editions = [edition(9, 3600), edition(4, 43_200)]
        #expect(HardcoverAPI.closestEdition(editions, to: 0)?.id == 9)
    }

    @Test("Editions with no length are not candidates")
    func skipsLengthless() {
        #expect(HardcoverAPI.closestEdition([edition(1, 0)], to: 3600) == nil)
        #expect(HardcoverAPI.closestEdition([], to: 3600) == nil)
    }

    @Test("Dates are sent as plain calendar days")
    func dateStamp() {
        let date = Date(timeIntervalSince1970: 1_757_000_000)
        let stamp = HardcoverAPI.dateStamp(date)
        #expect(stamp.count == 10)
        #expect(stamp.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil)
    }
}
