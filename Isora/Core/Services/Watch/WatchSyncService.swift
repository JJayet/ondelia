import Foundation
import WatchConnectivity

/// The iPhone half of the Apple Watch link: one `WCSession` delegate, the library snapshot the
/// watch draws from, the events and transport commands it sends back, and the chapter transfers.
///
/// Every delegate callback lands on a private serial queue, so each one pulls the `Sendable`
/// bytes it needs out of the WatchConnectivity objects and hops to the main actor before
/// touching a manager or the store.
@MainActor
@Observable
final class WatchSyncService: NSObject, WCSessionDelegate {
    static let shared = WatchSyncService()

    private(set) var isPaired = false
    private(set) var isWatchAppInstalled = false
    private(set) var isReachable = false
    /// Chapter numbers the watch reports holding, per book. Drives the snapshot order, the
    /// "on the watch" lines in the UI and the transfer-queue pruning.
    private(set) var chaptersOnWatch: [UUID: Set<Int>] = [:]

    /// Nil until `activate()`, and on a device with no WatchConnectivity at all — every send
    /// goes through it, so nothing else has to check twice.
    var session: WCSession?

    // Set from the extensions; `private` would put them out of reach.
    var snapshotTask: Task<Void, Never>?
    var lastProgressSentAt: Date = .distantPast
    /// Playback state as of the last hook, so "the phone started playing" fires on the edge and
    /// not on every seek, skip and speed change made while it plays.
    var wasPlaying = false
    var isDraining = false
    var transferObservations: [String: NSKeyValueObservation] = [:]
    var lastTransferProgressAt: Date = .distantPast

    private override init() { super.init() }

    /// Called once at launch. Safe on a device with no watch: `isSupported` is false there and
    /// the service stays inert.
    func activate() {
        guard WCSession.isSupported(), session == nil else { return }
        let session = WCSession.default
        self.session = session
        session.delegate = self
        session.activate()
        Log.sync.info("⌚️ WatchSyncService: activating")
    }

    func book(_ id: UUID) -> AudiobookModel? {
        AudiobookManager.shared.audiobooks.first { $0.id == id }
    }

    /// Sends one event. The default is the queued, guaranteed transfer. `urgent` events —
    /// "pause, I am playing" and a transfer's progress — are only worth anything immediately,
    /// so they go by `sendMessage` while the watch is reachable and are dropped when it is not.
    func send(_ event: SyncEvent, urgent: Bool = false) {
        guard let session, session.activationState == .activated, session.isWatchAppInstalled,
              let data = try? SyncCodec.encode(event) else { return }
        guard urgent else {
            session.transferUserInfo([SyncKeys.event: data])
            return
        }
        guard session.isReachable else { return }
        session.sendMessage([SyncKeys.event: data], replyHandler: nil) { error in
            Log.sync.debug("⌚️ WatchSyncService: message dropped — \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Watch state

    func applyState(paired: Bool, installed: Bool, reachable: Bool) {
        isPaired = paired
        isWatchAppInstalled = installed
        isReachable = reachable
    }

    /// One chapter appeared on, or disappeared from, the watch.
    func markOnWatch(bookID: UUID, chapterNumber: Int, present: Bool) {
        if present {
            chaptersOnWatch[bookID, default: []].insert(chapterNumber)
        } else {
            chaptersOnWatch[bookID]?.remove(chapterNumber)
        }
        pushSnapshot()
    }

    func setInventory(bookID: UUID, chapters: Set<Int>) {
        chaptersOnWatch[bookID] = chapters
        // Anything already on the watch has no business in the send queue.
        for number in chapters {
            WatchTransferQueue.shared.remove(bookID: bookID, chapterNumber: number)
        }
        pushSnapshot()
    }

    /// Tells the watch to delete everything it holds. It answers with a fresh inventory, which
    /// is what actually clears `chaptersOnWatch`.
    func clearWatch() {
        for bookID in chaptersOnWatch.keys {
            send(.bookCleared(bookID: bookID))
            WatchTransferQueue.shared.clear(bookID: bookID)
        }
        chaptersOnWatch.removeAll()
        pushSnapshot()
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        let state = watchState(of: session)
        let activated = activationState == .activated
        let failure = error?.localizedDescription
        Task { @MainActor in
            self.applyState(paired: state.paired, installed: state.installed, reachable: state.reachable)
            if let failure {
                Log.sync.error("❌ WatchSyncService: activation failed — \(failure, privacy: .public)")
            }
            guard activated else { return }
            self.pushSnapshot(immediate: true)
            self.drainQueue()
        }
    }

    /// The selected watch is being swapped: no new transfers until it is reactivated.
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in
            self.applyState(paired: self.isPaired, installed: false, reachable: false)
        }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in self.session?.activate() }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        let state = watchState(of: session)
        Task { @MainActor in
            self.applyState(paired: state.paired, installed: state.installed, reachable: state.reachable)
            guard state.installed else { return }
            self.pushSnapshot()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let state = watchState(of: session)
        Task { @MainActor in
            self.applyState(paired: state.paired, installed: state.installed, reachable: state.reachable)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        route(userInfo, reply: nil)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        route(message, reply: nil)
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        route(message, reply: replyHandler)
    }

    nonisolated func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: (any Error)?
    ) {
        let url = fileTransfer.file.fileURL
        let metadata = TransferMetadata(dictionary: fileTransfer.file.metadata ?? [:])
        let failure = error?.localizedDescription
        Task { @MainActor in
            self.finishTransfer(at: url, metadata: metadata, error: failure)
        }
    }

    // MARK: - Routing

    /// `[String: Any]` cannot cross an actor boundary, so the payload is reduced to its bytes
    /// here, on the delegate queue, and only `Data` makes the hop.
    private nonisolated func route(_ payload: [String: Any], reply: (([String: Any]) -> Void)?) {
        let event = payload[SyncKeys.event] as? Data
        let command = payload[SyncKeys.command] as? Data
        // The reply handler is not `Sendable` and never will be. It is called once, from the hop
        // below, and that is the whole of the risk.
        nonisolated(unsafe) let reply = reply
        Task { @MainActor in
            if let event, let decoded = try? SyncCodec.decode(SyncEvent.self, from: event) {
                self.handle(decoded)
            }
            if let command, let decoded = try? SyncCodec.decode(RemoteCommand.self, from: command) {
                await self.perform(decoded)
            }
            guard let reply else { return }
            guard let data = self.sendSnapshot() else {
                reply([:])
                return
            }
            reply([SyncKeys.snapshot: data])
        }
    }

    private nonisolated func watchState(
        of session: WCSession
    ) -> (paired: Bool, installed: Bool, reachable: Bool) {
        (session.isPaired, session.isWatchAppInstalled, session.isReachable)
    }
}
