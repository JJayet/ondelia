import Foundation
import WatchConnectivity

/// The watch end of the link. Owns the `WCSession`, applies whatever the phone pushes into the
/// local store, and is the only place that sends anything back.
///
/// Every delegate callback arrives off the main actor, so each one pulls the `Sendable` payload
/// out of the (non-`Sendable`) dictionary it was handed and hops to the main actor from there.
@MainActor
@Observable
final class PhoneSyncService: NSObject, WCSessionDelegate {
    static let shared = PhoneSyncService()

    /// What the phone says it is playing, nil when it is silent.
    var phoneNowPlaying: NowPlayingState?
    /// Book order as the phone sent it — "content on the watch first, then most recent".
    var bookOrder: [UUID] = []
    var isReachable = false
    var isPhoneAppInstalled = false

    private override init() { super.init() }

    private var session: WCSession? {
        WCSession.isSupported() ? .default : nil
    }

    func activate() {
        guard let session else {
            Log.sync.error("❌ PhoneSyncService: WCSession unsupported")
            return
        }
        session.delegate = self
        session.activate()
    }

    // MARK: - Outgoing

    /// The default is the queued, guaranteed transfer. `urgent` events — "pause, I am playing" —
    /// are only worth anything immediately, so they go by `sendMessage` while the phone is
    /// reachable and fall back to the queue when it is not.
    func send(_ event: SyncEvent, urgent: Bool = false) {
        guard let session, session.activationState == .activated,
              let data = try? SyncCodec.encode(event) else { return }
        let payload: [String: Any] = [SyncKeys.event: data]
        guard urgent, session.isReachable else {
            session.transferUserInfo(payload)
            return
        }
        session.sendMessage(payload, replyHandler: nil) { error in
            Log.sync.debug("⌚️ PhoneSyncService: message dropped — \(error.localizedDescription)")
        }
    }

    /// Transport control of the phone. `sendMessage` answers with a fresh snapshot, so the watch
    /// sees the result without waiting for the next application context.
    func send(_ command: RemoteCommand) {
        guard let session, session.activationState == .activated,
              let data = try? SyncCodec.encode(command) else { return }
        let payload: [String: Any] = [SyncKeys.command: data]
        guard session.isReachable else {
            session.transferUserInfo(payload)
            return
        }
        session.sendMessage(payload) { reply in
            guard let snapshot = reply[SyncKeys.snapshot] as? Data else { return }
            Task { @MainActor in PhoneSyncService.shared.applySnapshot(data: snapshot) }
        } errorHandler: { error in
            Log.sync.error("❌ PhoneSyncService: command failed: \(error.localizedDescription)")
        }
    }

    func requestChapter(bookID: UUID, number: Int) {
        WatchTransferState.shared.markRequested(bookID: bookID, chapter: number)
        send(SyncEvent.chapterRequested(bookID: bookID, chapterNumber: number))
    }

    func sendInventory(bookID: UUID) {
        send(SyncEvent.watchInventory(bookID: bookID, chapterNumbers: chaptersOnDisk(bookID: bookID)))
    }

    // MARK: - Inventory

    func chaptersOnDisk(bookID: UUID) -> [Int] {
        WatchLibraryDisk.chaptersOnDisk(bookID: bookID)
    }

    func bytesOnDisk() -> Int64 {
        WatchLibraryDisk.bytesOnDisk()
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        if let error {
            Log.sync.error("❌ PhoneSyncService: activation failed: \(error.localizedDescription)")
        }
        let reachable = session.isReachable
        let installed = session.isCompanionAppInstalled
        let context = session.receivedApplicationContext[SyncKeys.snapshot] as? Data
        Task { @MainActor in
            let service = PhoneSyncService.shared
            service.isReachable = reachable
            service.isPhoneAppInstalled = installed
            WatchTransferState.shared.refreshAll()
            if let context { service.applySnapshot(data: context) }
            // The phone keeps its picture of what the watch holds in memory only, so it starts
            // every launch believing the watch is empty. This is what corrects it.
            for bookID in WatchLibraryDisk.bookIDsWithContent() { service.sendInventory(bookID: bookID) }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        let installed = session.isCompanionAppInstalled
        Task { @MainActor in
            PhoneSyncService.shared.isReachable = reachable
            PhoneSyncService.shared.isPhoneAppInstalled = installed
        }
    }

    nonisolated func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        let installed = session.isCompanionAppInstalled
        Task { @MainActor in PhoneSyncService.shared.isPhoneAppInstalled = installed }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[SyncKeys.snapshot] as? Data else { return }
        Task { @MainActor in PhoneSyncService.shared.applySnapshot(data: data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[SyncKeys.event] as? Data else { return }
        Task { @MainActor in PhoneSyncService.shared.handle(eventData: data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message[SyncKeys.event] as? Data else { return }
        Task { @MainActor in PhoneSyncService.shared.handle(eventData: data) }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        replyHandler([:])
        guard let data = message[SyncKeys.event] as? Data else { return }
        Task { @MainActor in PhoneSyncService.shared.handle(eventData: data) }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // WatchConnectivity deletes the file as soon as this returns, so the move is synchronous
        // and happens here, on whatever queue the callback arrived on.
        guard let metadata = TransferMetadata(dictionary: file.metadata ?? [:]) else {
            Log.sync.error("❌ PhoneSyncService: file with no usable metadata")
            return
        }
        switch metadata.kind {
        case .cover:
            guard let data = try? Data(contentsOf: file.fileURL) else { return }
            let bookID = metadata.bookID
            Task { @MainActor in PhoneSyncService.shared.applyCover(data, to: bookID) }
        case .chapter:
            guard let number = metadata.chapterNumber,
                  Self.moveChapterFile(at: file.fileURL, bookID: metadata.bookID, number: number) else { return }
            let bookID = metadata.bookID
            Task { @MainActor in PhoneSyncService.shared.didLandChapter(bookID: bookID, number: number) }
        }
    }
}
