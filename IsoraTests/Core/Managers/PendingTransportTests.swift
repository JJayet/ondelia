import Foundation
import Testing
@testable import Isora

/// Transport requests that arrive while a book is still loading. Every one of these used to be
/// dropped on the floor: the player does not exist yet, and nothing remembered the request.
@MainActor
@Suite("Pending transport during a load", .serialized)
struct PendingTransportTests {

    /// The manager is a singleton other suites have already played with, so each test starts
    /// from a torn-down one rather than from whatever was left behind.
    private func idleManager() -> GlobalAudioManager {
        let manager = GlobalAudioManager.shared
        manager.unload()
        return manager
    }

    @Test("A seek during a load is remembered for the player that is coming")
    func seekDuringLoadIsQueued() {
        let manager = idleManager()
        manager.isLoading = true

        manager.seek(to: 42)

        #expect(manager.pendingSeek == 42)
        manager.isLoading = false
        manager.pendingSeek = nil
    }

    @Test("A seek with nothing loading is dropped rather than queued")
    func seekWithoutLoadIsIgnored() {
        let manager = idleManager()

        manager.seek(to: 42)

        #expect(manager.pendingSeek == nil)
    }

    @Test("Pausing during a load cancels the playback it was queued to start")
    func pauseClearsQueuedPlayback() {
        let manager = idleManager()
        manager.isLoading = true
        manager.resumePlayback()
        #expect(manager.pendingAutoplay)

        manager.pausePlayback()

        #expect(manager.pendingAutoplay == false)
        manager.isLoading = false
    }
}
