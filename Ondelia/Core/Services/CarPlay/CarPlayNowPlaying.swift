import CarPlay
import UIKit

/// Dresses the system Now Playing screen. Transport, artwork and title come from
/// `MPRemoteCommandCenter` and `MPNowPlayingInfoCenter`, which `GlobalAudioManager` already
/// feeds; this adds the speed and bookmark lists behind their buttons, and the chapter list
/// behind "Up Next".
@MainActor
final class CarPlayNowPlaying: NSObject, @preconcurrency CPNowPlayingTemplateObserver {
    private weak var interfaceController: CPInterfaceController?

    init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        super.init()

        let template = CPNowPlayingTemplate.shared
        template.add(self)
        template.isUpNextButtonEnabled = true
        template.upNextTitle = NSLocalizedString("Chapters", comment: "Chapter list sheet title")

        // Not `CPNowPlayingPlaybackRateButton`: its label stayed at "0x" whatever the app published.
        let speedImage = UIImage(systemName: "gauge.with.dots.needle.67percent") ?? UIImage()
        let rate = CPNowPlayingImageButton(image: speedImage) { [weak self] _ in
            MainActor.assumeIsolated { self?.showSpeeds() }
        }
        let bookmark = CPNowPlayingImageButton(image: UIImage(systemName: "bookmark") ?? UIImage()) { [weak self] _ in
            MainActor.assumeIsolated { self?.showBookmarks() }
        }
        template.updateNowPlayingButtons([rate, bookmark])
    }

    func tearDown() {
        let template = CPNowPlayingTemplate.shared
        template.remove(self)
        template.isUpNextButtonEnabled = false
        template.updateNowPlayingButtons([])
    }

    // MARK: - Buttons

    /// The player's speed list, with the current one marked.
    private func showSpeeds() {
        let audio = GlobalAudioManager.shared
        let current = audio.getPlaybackRate()
        let items = PlaybackSpeed.choices.map { speed in
            let item = CPListItem(text: PlaybackSpeed.displayName(speed), detailText: nil)
            item.isPlaying = abs(speed - current) < 0.01
            item.playingIndicatorLocation = .trailing
            item.handler = { [weak self] _, completion in
                GlobalAudioManager.shared.setPlaybackRate(speed)
                self?.interfaceController?.popTemplate(animated: true) { _, _ in completion() }
            }
            return item
        }
        let template = CPListTemplate(
            title: NSLocalizedString("Speed", comment: "Playback speed picker label"),
            sections: [CPListSection(items: items)]
        )
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    // MARK: - Bookmarks

    /// "Add Bookmark" on top, then the book's bookmarks in the order the phone lists them.
    private func showBookmarks() {
        guard let book = GlobalAudioManager.shared.currentAudiobook else { return }
        let add = CPListItem(
            text: NSLocalizedString("Add Bookmark", comment: "Add bookmark button title"),
            detailText: nil,
            image: UIImage(systemName: "bookmark")
        )
        add.handler = { [weak self] _, completion in
            PlaybackCommands.addBookmark()
            self?.interfaceController?.popTemplate(animated: true) { _, _ in completion() }
        }
        let bookmarks = book.bookmarks.sorted { $0.timestamp < $1.timestamp }
            .prefix(CPListTemplate.maximumItemCount - 1)
            .map { bookmark in
                let item = CPListItem(
                    text: bookmark.title ?? NSLocalizedString("Bookmark", comment: "Default bookmark title"),
                    detailText: bookmark.timestamp.clockFormatted
                )
                let time = bookmark.timestamp
                item.handler = { [weak self] _, completion in
                    GlobalAudioManager.shared.seek(to: time)
                    self?.interfaceController?.popTemplate(animated: true) { _, _ in completion() }
                }
                return item
            }
        let template = CPListTemplate(
            title: NSLocalizedString("Bookmarks", comment: "Bookmarks view title"),
            sections: [CPListSection(items: [add] + bookmarks)]
        )
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    // MARK: - Chapters

    func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        let audio = GlobalAudioManager.shared
        guard let book = audio.currentAudiobook else { return }
        // Chapters are matched by time, not index: the player's chapter index counts files,
        // and a single-file book has one.
        let now = audio.getCurrentTime()
        let items = book.sortedChapters.prefix(CPListTemplate.maximumItemCount).enumerated().map { index, chapter in
            let item = CPListItem(
                text: chapter.title
                    ?? String(format: NSLocalizedString("Chapter %d", comment: "Default chapter title with number"), index + 1),
                detailText: (chapter.endTime - chapter.startTime).clockFormatted
            )
            item.isPlaying = now >= chapter.startTime && now < chapter.endTime
            item.playingIndicatorLocation = .trailing
            item.handler = { [weak self] _, completion in
                GlobalAudioManager.shared.seek(to: chapter.startTime)
                self?.interfaceController?.popTemplate(animated: true) { _, _ in completion() }
            }
            return item
        }
        let template = CPListTemplate(
            title: NSLocalizedString("Chapters", comment: "Chapter list sheet title"),
            sections: [CPListSection(items: Array(items))]
        )
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }
}
