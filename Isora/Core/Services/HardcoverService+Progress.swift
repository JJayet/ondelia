import Foundation

// MARK: - Progress sync
//
// Two things are pushed as a book plays: the shelf it belongs on, and how far into it the
// listener is. They are separate requests with separate reasons to stay quiet, so they are
// separate functions.
extension HardcoverService {
    /// Pushes the shelf status and the listening position, if either has moved far enough to
    /// be worth a request.
    ///
    /// Called on every progress write — every five seconds while a book plays — so the cheap
    /// guards come first and both halves below decide for themselves whether to say anything.
    func syncProgress(for audiobook: AudiobookModel) async {
        guard let token, audiobook.hardcover != nil, !syncing.contains(audiobook.id) else { return }

        syncing.insert(audiobook.id)
        defer { syncing.remove(audiobook.id) }

        await pushStatus(for: audiobook, token: token)
        await pushProgress(for: audiobook, token: token)
    }

    /// Moves the book to the shelf its progress now implies. Only ever forward: re-opening a
    /// finished book must not push it back to "currently reading".
    func pushStatus(for audiobook: AudiobookModel, token: String) async {
        guard let link = audiobook.hardcover else { return }

        let target: HardcoverLink.Status
        if audiobook.isFinished {
            target = .read
        } else if audiobook.progressFraction * 100 >= readingThreshold {
            target = .reading
        } else {
            return
        }
        guard target > link.status else { return }

        do {
            let userBookID = try await HardcoverAPI.setStatus(
                bookID: link.id, status: target, token: token
            )
            // Re-read: an await let the book be unlinked or relinked while the request was out.
            guard var current = audiobook.hardcover, current.id == link.id else { return }
            current.status = target
            current.userBookID = userBookID
            audiobook.hardcover = current
            save()
            Log.hardcover.info("Pushed status \(target.rawValue, privacy: .public) to Hardcover")
        } catch {
            Log.hardcover.error("Failed to push status: \(error.localizedDescription)")
        }
    }

    /// Pushes the listening position, so Hardcover shows the percentage the app shows — an hour
    /// into a twelve-hour book reads as 8% on both.
    ///
    /// Hardcover measures seconds against an audiobook edition, so the first push looks one up
    /// and remembers it on the link. The read row is opened once and moved after that, rather
    /// than a new one opened per push, which would read as re-reading the book every minute.
    func pushProgress(for audiobook: AudiobookModel, token: String) async {
        guard var link = audiobook.hardcover,
              let userBookID = link.userBookID,
              link.status >= .reading,
              audiobook.duration > 0
        else { return }

        // `Int(_:)` traps on a non-finite or out-of-range Double, and this position has crossed
        // both AVFoundation and the store to get here. Clamping to the book's own length bounds
        // it in one step.
        let position = audiobook.currentPosition
        guard position.isFinite else { return }
        let seconds = Int(min(max(position, 0), audiobook.duration).rounded())

        // A finished book always gets its push: it carries the finish date with it.
        if !audiobook.isFinished,
           let attempted = attemptedSeconds[audiobook.id],
           abs(seconds - attempted) < Self.progressPushInterval { return }

        if link.editionID == nil, link.editionChecked != true {
            do {
                let edition = try await HardcoverAPI.audiobookEdition(
                    bookID: link.id, matching: audiobook.duration, token: token
                )
                guard var current = audiobook.hardcover, current.id == link.id else { return }
                current.editionID = edition?.id
                current.editionChecked = true
                audiobook.hardcover = current
                link = current
                save()
                if edition == nil {
                    // The seconds are still worth sending; Hardcover just has nothing to divide
                    // them by, so the profile shows the shelf but no percentage.
                    Log.hardcover.info("No audiobook edition on Hardcover for this book")
                }
            } catch {
                Log.hardcover.error("Failed to look up the audiobook edition: \(error.localizedDescription)")
                return
            }
        }

        // Recorded before the request, not after it. Recording only successes turns an outage
        // into a request every five seconds for as long as the book plays, and a rejected token
        // into one that never stops. A failed push is not lost progress: the next one sends the
        // position as it is by then, which supersedes it anyway.
        attemptedSeconds[audiobook.id] = seconds

        let today = HardcoverAPI.dateStamp(Date())
        do {
            if let readID = link.readID {
                try await HardcoverAPI.updateRead(
                    id: readID,
                    editionID: link.editionID,
                    seconds: seconds,
                    finishedAt: audiobook.isFinished ? today : nil,
                    token: token
                )
            } else {
                let readID = try await HardcoverAPI.startRead(
                    userBookID: userBookID,
                    editionID: link.editionID,
                    seconds: seconds,
                    startedAt: today,
                    finishedAt: audiobook.isFinished ? today : nil,
                    token: token
                )
                guard var current = audiobook.hardcover, current.id == link.id else { return }
                current.readID = readID
                audiobook.hardcover = current
                save()
            }
        } catch {
            Log.hardcover.error("Failed to push progress: \(error.localizedDescription)")
        }
    }
}
