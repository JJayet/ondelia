import XCTest
@testable import AudiobookReader

final class PlayerViewModelTests: XCTestCase {
    func testSleepTimerSetsAndCancels() throws {
        let mockAudio = MockAudioManager()
        let deps = MockDependencies(audioManager: mockAudio)
        let book = AudiobookModel()
        let stats = deps.createReadingStatistics() as! MockReadingStatistics
        let sut = PlayerViewModel(audiobook: book, dependencies: deps, statistics: stats)

        sut.setSleepTimer(2)
        XCTAssertEqual(sut.sleepTimeRemaining, 2)

        sut.cancelSleepTimer()
        XCTAssertEqual(sut.sleepTimeRemaining, 0)
    }

    func testOnTickAdvancesProgressWhenPlaying() throws {
        let mockAudio = MockAudioManager()
        mockAudio.setMockDuration(100)
        mockAudio.setMockCurrentTime(10)
        mockAudio.startPlayback()

        let mockManager = MockAudiobookManager()
        let deps = MockDependencies(audioManager: mockAudio, audiobookManager: mockManager)
        let book = AudiobookModel()
        let stats = deps.createReadingStatistics() as! MockReadingStatistics
        let sut = PlayerViewModel(audiobook: book, dependencies: deps, statistics: stats)

        sut.onTick()
        XCTAssertGreaterThanOrEqual(stats.totalListeningTime, 1)
    }
}

