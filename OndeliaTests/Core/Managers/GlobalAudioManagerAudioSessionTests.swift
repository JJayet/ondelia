import Foundation
import AVFoundation
import Testing
@testable import Isora

/// Loads the real 2.5 s AAC fixture into the shared manager and waits for it to be ready.
/// The model claims an hour, so a position written mid-file is never near enough the end to
/// count as a Finish.
@MainActor
func loadFixtureBook(into manager: GlobalAudioManager) async throws -> AudiobookModel {
    manager.unload()
    let book = AudiobookModel(title: "Fixture", author: "Test", duration: 3600)
    book.fileURL = try #require(Bundle(for: TestBundleAnchor.self).url(forResource: "sample", withExtension: "m4a")).path
    manager.loadAudiobook(book)
    try #require(await waitUntil(timeout: 5) { manager.isReady && manager.player != nil })
    return book
}

/// Interruptions and route changes, driven by posting the notifications AVAudioSession posts.
/// Serialized: the manager and the audio session are both process-wide. Pauses are awaited for
/// well under the fixture's 2.5 s, so the book ending on its own cannot pass for one.
@MainActor
@Suite("GlobalAudioManager audio session", .serialized)
struct GlobalAudioManagerAudioSessionTests {
    private let manager = GlobalAudioManager.shared

    private func startPlaying() async throws {
        _ = try await loadFixtureBook(into: manager)
        manager.resumePlayback()
        try #require(await waitUntil { manager.isPlaying() })
    }

    private func interrupt(_ type: AVAudioSession.InterruptionType, shouldResume: Bool = false) {
        var info: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: type.rawValue]
        if shouldResume {
            info[AVAudioSessionInterruptionOptionKey] = AVAudioSession.InterruptionOptions.shouldResume.rawValue
        }
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: info)
    }

    private func changeRoute(_ reason: AVAudioSession.RouteChangeReason) {
        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey: reason.rawValue]
        )
    }

    @Test("An interruption pauses, and its end resumes when the system says so")
    func interruptionPausesThenResumes() async throws {
        try await startPlaying()
        defer { manager.unload() }

        interrupt(.began)
        #expect(await waitUntil(timeout: 0.5) { manager.playbackState == .paused })
        #expect(manager.isPlaying() == false)

        interrupt(.ended, shouldResume: true)
        #expect(await waitUntil { manager.playbackState == .playing })
        #expect(manager.isPlaying())
    }

    @Test("An interruption that ends without shouldResume stays paused")
    func interruptionWithoutResumeStaysPaused() async throws {
        try await startPlaying()
        defer { manager.unload() }

        interrupt(.began)
        #expect(await waitUntil(timeout: 0.5) { manager.playbackState == .paused })

        interrupt(.ended)
        try await Task.sleep(for: .milliseconds(300))
        #expect(manager.playbackState == .paused)
        #expect(manager.isPlaying() == false)
    }

    @Test("An interruption while paused does not start playback when it ends")
    func interruptionWhilePausedDoesNotResume() async throws {
        _ = try await loadFixtureBook(into: manager)
        defer { manager.unload() }

        interrupt(.began)
        try await Task.sleep(for: .milliseconds(200))
        interrupt(.ended, shouldResume: true)
        try await Task.sleep(for: .milliseconds(300))

        #expect(manager.playbackState == .paused)
        #expect(manager.isPlaying() == false)
    }

    @Test("Headphones pulled out pause playback")
    func oldDeviceUnavailablePauses() async throws {
        try await startPlaying()
        defer { manager.unload() }

        changeRoute(.oldDeviceUnavailable)

        #expect(await waitUntil(timeout: 0.5) { manager.playbackState == .paused })
        #expect(manager.isPlaying() == false)
    }

    @Test("A new output appearing keeps playing")
    func newDeviceAvailableKeepsPlaying() async throws {
        try await startPlaying()
        defer { manager.unload() }

        changeRoute(.newDeviceAvailable)
        try await Task.sleep(for: .milliseconds(300))

        #expect(manager.playbackState == .playing)
        #expect(manager.isPlaying())
    }
}
