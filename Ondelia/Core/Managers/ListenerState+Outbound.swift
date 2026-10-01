import Foundation

// MARK: - The app's outbound adapters
extension ListenerState {
    static let shared = ListenerState(
        store: .shared,
        statistics: .shared,
        outbound: [.audiobookShelf, .hardcover, .watch, .player, .library]
    )
}

extension ListenerState.Outbound {
    /// No-op unless the audiobook is linked to a signed-in server; throttles itself.
    static let audiobookShelf = Self(source: .server) { accepted in
        AudiobookShelfService.shared.pushProgress(for: accepted.audiobook)
    }

    /// No-op unless the audiobook has a Hardcover link; throttles itself.
    static let hardcover = Self(source: nil) { accepted in
        Task { await HardcoverService.shared.syncProgress(for: accepted.audiobook) }
    }

    /// The playback tick is throttled for the watch; anything else is news straight away.
    static let watch = Self(source: .watch) { accepted in
        if accepted.source == .player {
            WatchSyncService.shared.phoneDidPersistProgress(for: accepted.audiobook)
        } else {
            WatchSyncService.shared.pushSnapshot()
        }
    }

    /// Moves the player to a position that arrived from elsewhere, but only when it is showing
    /// this audiobook and silent: seeking under a playing listener is worse than a few seconds
    /// of drift. Otherwise the next tick would write the player's stale time back over it.
    static let player = Self(source: .player) { accepted in
        switch accepted.change {
        case .position, .reset: break
        case .finish, .unfinish: return
        }
        let audio = GlobalAudioManager.shared
        guard audio.currentAudiobook?.id == accepted.audiobook.id, !audio.isPlaying() else { return }
        audio.seek(to: accepted.audiobook.currentPosition, rememberOrigin: false)
    }

    /// Finished audiobooks sort and filter differently; a position alone does not reorder.
    static let library = Self(source: nil) { accepted in
        guard accepted.finishedChanged else { return }
        AudiobookManager.shared.fetchAudiobooks()
    }
}
