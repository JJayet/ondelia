import Testing
import AVFoundation
@testable import AudiobookReader

/// Playback tests against a real 2.5 s AAC fixture (TestResources/SampleAudioFiles/sample.m4a).
// Other suites create AudioEngines concurrently and share the process-wide AVAudioSession;
// their interruption/route-change handling can pause this engine mid-test, so play() is re-issued while polling.
@Suite(.serialized)
@MainActor
struct AudioEnginePlaybackTests {

    private func fixtureURL() throws -> URL {
        try #require(Bundle(for: MockAVAudioSession.self).url(forResource: "sample", withExtension: "m4a"))
    }

    /// Polls `condition` every 50 ms until true or `timeout` elapses.
    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    @Test("Loads fixture and reports its duration")
    func loadReportsDuration() async throws {
        let engine = AudioEngine()
        engine.loadAudio(url: try fixtureURL())
        #expect(await waitUntil { engine.duration > 0 })
        #expect(abs(engine.duration - 2.53) < 0.3)
    }

    @Test("Play starts playback and advances time")
    func playAdvancesTime() async throws {
        let engine = AudioEngine()
        engine.loadAudio(url: try fixtureURL())
        #expect(await waitUntil { engine.duration > 0 })
        engine.play()
        #expect(await waitUntil(10) {
            if !engine.isPlaying { engine.play() }
            return engine.isPlaying && engine.currentTime > 0.2
        })
        engine.pause()
        #expect(await waitUntil { !engine.isPlaying })
    }

    @Test("Seek moves current time")
    func seekMovesTime() async throws {
        let engine = AudioEngine()
        engine.loadAudio(url: try fixtureURL())
        #expect(await waitUntil { engine.duration > 0 })
        engine.seek(to: 1.5)
        #expect(await waitUntil { engine.currentTime >= 1.3 })
        #expect(engine.currentTime < 2.6)
    }
}
