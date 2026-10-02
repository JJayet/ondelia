import Foundation

/// The listener's Position and Finishes for every audiobook, and the one way to change them.
///
/// Every source — the player, the listener's own actions, an AudiobookShelf pull, the watch —
/// hands its change to `apply`. The rules live here once: last write wins, a position near the
/// end is a Finish, the store is saved, and every outbound adapter except the one the change
/// came from hears about it. Before this, seven writers each remembered a different subset.
///
/// CloudKit merges are not a source: they land in the store directly, and the device that made
/// them already told its own outbound adapters.
@MainActor
final class ListenerState {
    enum Change: Equatable {
        case position(TimeInterval)
        case finish
        case unfinish
        /// Back to the start. Leaves Finished alone: starting over is not retracting a Finish.
        case reset
    }

    enum Source: Equatable {
        /// The playback tick and the end of an audiobook.
        case player
        /// Library, Search, the actions menu, CarPlay, App Intents.
        case listener
        /// An AudiobookShelf pull.
        case server
        case watch

        /// Remote sources carry their own timestamp and lose to a newer local write.
        var isRemote: Bool { self == .server || self == .watch }
    }

    /// One change `apply` accepted, as the outbound adapters see it.
    struct Accepted {
        let change: Change
        let audiobook: AudiobookModel
        let source: Source
        /// Whether Finished flipped, which reorders the Library.
        let finishedChanged: Bool
    }

    /// Something that has to hear about accepted changes: a remote, the player, the Library.
    struct Outbound {
        /// The source this adapter speaks for. It is not told about its own changes back.
        let source: Source?
        let notify: @MainActor (Accepted) -> Void
    }

    /// A position this close to the end is a Finish.
    static let finishThreshold: TimeInterval = 30
    /// A remote timestamp within this much of the local one is the same moment: the clocks
    /// on the phone, the watch and the server are not one clock.
    static let clockSlack: TimeInterval = 1

    let store: SwiftDataController
    let statistics: ReadingStatistics
    private let outbound: [Outbound]
    private let clock: () -> Date

    init(
        store: SwiftDataController,
        statistics: ReadingStatistics,
        outbound: [Outbound],
        clock: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.statistics = statistics
        self.outbound = outbound
        self.clock = clock
    }

    /// Applies `change` from `source`. Local changes are stamped now; remote ones pass the time
    /// they were made. Returns false when a remote position lost to a newer local one, in which
    /// case nothing was written and nobody was told.
    @discardableResult
    func apply(_ change: Change, to audiobook: AudiobookModel, from source: Source, at date: Date? = nil) -> Bool {
        let at = date ?? clock()
        let wasFinished = audiobook.isFinished

        switch change {
        case let .position(time):
            if source.isRemote, !Self.isNewer(at, than: audiobook.positionUpdatedAt) { return false }
            setPosition(time, of: audiobook, at: at)
            // Smart rewind measures the pause from `lastPlayed`. A remote listen that stopped
            // here is the last play, but never moves it back.
            audiobook.lastPlayed = source.isRemote ? max(audiobook.lastPlayed, at) : at
            // AudiobookShelf says outright whether it is finished; its position near the end
            // may just be a listener who stopped before the credits.
            if source != .server, audiobook.duration > 0, audiobook.duration - time <= Self.finishThreshold {
                recordFinish(audiobook, from: source, at: at)
            }
        case .finish:
            recordFinish(audiobook, from: source, at: at)
            // Marked by hand: the position follows, so resuming does not replay the last chapter.
            if source == .listener { setPosition(audiobook.duration, of: audiobook, at: at) }
        case .unfinish:
            retractFinish(audiobook, from: source)
        case .reset:
            setPosition(0, of: audiobook, at: at)
        }

        store.save()
        let accepted = Accepted(
            change: change,
            audiobook: audiobook,
            source: source,
            finishedChanged: audiobook.isFinished != wasFinished
        )
        for adapter in outbound where adapter.source != source {
            adapter.notify(accepted)
        }
        return true
    }

    /// Last write wins. A local position with no timestamp predates position sync and loses.
    static func isNewer(_ remote: Date, than local: Date?) -> Bool {
        guard let local else { return true }
        return remote > local.addingTimeInterval(clockSlack)
    }

    private func setPosition(_ time: TimeInterval, of audiobook: AudiobookModel, at: Date) {
        audiobook.currentPosition = time
        audiobook.positionUpdatedAt = at
    }
}
