import XCTest
@testable import AudiobookReader

@MainActor
final class PlayerViewModelTests: XCTestCase {
    func testSleepTimerSetsAndCancels() throws {
        let deps = MockDependencies(audioManager: MockAudioManager())
        let sut = PlayerViewModel(audiobook: AudiobookModel(), dependencies: deps, statistics: ReadingStatistics())

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

        let deps = MockDependencies(audioManager: mockAudio, audiobookManager: MockAudiobookManager())
        let stats = ReadingStatistics()
        let before = stats.totalListeningTime
        let sut = PlayerViewModel(audiobook: AudiobookModel(), dependencies: deps, statistics: stats)

        sut.onTick()
        XCTAssertEqual(stats.totalListeningTime, before + 1)
    }
}
