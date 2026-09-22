import CarPlay
import UIKit

/// Dresses the system Now Playing screen. Transport, artwork and title come from
/// `MPRemoteCommandCenter` and `MPNowPlayingInfoCenter`, which `GlobalAudioManager` already
/// feeds; this adds the speed and bookmark buttons and the chapter list behind "Up Next".
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

        let rate = CPNowPlayingPlaybackRateButton { _ in
            MainActor.assumeIsolated { Self.cycleSpeed() }
        }
        let bookmark = CPNowPlayingImageButton(image: UIImage(systemName: "bookmark") ?? UIImage()) { _ in
            MainActor.assumeIsolated { Self.addBookmark() }
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

    /// Next speed in the player's list, wrapping to the slowest after the fastest.
    private static func cycleSpeed() {
        let audio = GlobalAudioManager.shared
        let current = audio.getPlaybackRate()
        let next = PlaybackSpeed.choices.first { $0 > current + 0.01 } ?? PlaybackSpeed.choices[0]
        audio.setPlaybackRate(next)
    }

    private static func addBookmark() { PlaybackCommands.addBookmark() }

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
