import Foundation

// MARK: - Undo the last seek
//
// A scrub that landed in the wrong place, a chapter tapped by mistake: the position it left is
// kept for a minute so one tap goes back. Only sizeable jumps count, and only ones the listener
// made — a sync from the watch or the load's own positioning never offers an undo.
extension GlobalAudioManager {
    static let undoSeekMinimumJump: TimeInterval = 10
    static let undoSeekLifetime: Duration = .seconds(60)

    /// Pure: whether a jump is worth offering to undo.
    static func isUndoableSeek(from: TimeInterval, to: TimeInterval) -> Bool {
        from.isFinite && to.isFinite && abs(to - from) >= undoSeekMinimumJump
    }

    /// Keeps the latest origin, not the first: a deliberate chapter jump followed by an accidental
    /// scrub should undo the scrub alone.
    func rememberSeekOrigin(_ origin: TimeInterval, target: TimeInterval) {
        guard Self.isUndoableSeek(from: origin, to: target) else { return }
        undoSeekOrigin = origin
        undoSeekTask?.cancel()
        undoSeekTask = Task { [weak self] in
            try? await Task.sleep(for: Self.undoSeekLifetime)
            guard !Task.isCancelled else { return }
            self?.undoSeekOrigin = nil
        }
    }

    /// Back to where the last seek started. Does not itself become undoable.
    func undoLastSeek() {
        guard let origin = undoSeekOrigin else { return }
        clearUndoSeek()
        performSeek(to: origin)
    }

    func clearUndoSeek() {
        undoSeekTask?.cancel()
        undoSeekTask = nil
        undoSeekOrigin = nil
    }
}
