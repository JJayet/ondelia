import CarPlay
import UIKit

/// The CarPlay scene. Named in `Info.plist` under `CPTemplateApplicationSceneSessionRoleApplication`;
/// the phone window stays with SwiftUI, which is why the manifest lists no other role.
///
/// CarPlay can launch the app straight into the background, before the store has opened and
/// before any phone view ran. The root tab bar goes up at once with empty lists, and the
/// library fills in once `SwiftDataController` reports loaded — the same wait `PlaybackCommands`
/// does for Siri and the widgets.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPInterfaceControllerDelegate {
    private var interfaceController: CPInterfaceController?
    private var library: CarPlayLibrary?
    private var nowPlaying: CarPlayNowPlaying?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        Log.audio.debug("🚗 CarPlay connected")
        self.interfaceController = interfaceController
        interfaceController.delegate = self
        // Registers the remote commands the Now Playing screen drives, when no phone view has
        // touched the manager yet.
        _ = GlobalAudioManager.shared

        let library = CarPlayLibrary(interfaceController: interfaceController)
        self.library = library
        nowPlaying = CarPlayNowPlaying(interfaceController: interfaceController)
        interfaceController.setRootTemplate(library.tabBar, animated: false, completion: nil)

        Task {
            await SwiftDataController.shared.whenLoaded()
            guard SwiftDataController.shared.isLoaded else { return }
            AudiobookManager.shared.fetchAudiobooks()
            library.reload()
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        Log.audio.debug("🚗 CarPlay disconnected")
        nowPlaying?.tearDown()
        nowPlaying = nil
        library = nil
        self.interfaceController = nil
    }

    // MARK: - CPInterfaceControllerDelegate

    /// A list is only stale while it is off screen, so rows are rebuilt on the way in rather
    /// than observed.
    func templateWillAppear(_ aTemplate: CPTemplate, animated: Bool) {
        library?.reload(aTemplate)
    }
}
