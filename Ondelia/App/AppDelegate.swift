import Intents
import UIKit

/// What SwiftUI's lifecycle has no hook for: handing the system an intent handler, and
/// background `URLSession` events.
///
/// `INPlayMediaIntent` is what the media suggestions replay when someone taps the app's cover
/// in Control Center, so it has to be answered in the app process where the player lives.
final class AppDelegate: NSObject, UIApplicationDelegate {
    private let mediaIntentHandler = MediaIntentHandler()

    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
        intent is INPlayMediaIntent ? mediaIntentHandler : nil
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Reconnects the AudiobookShelf background session, so downloads that finished while
        // the app was not running are delivered and imported.
        _ = AudiobookShelfService.shared
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == AudiobookShelfDownloader.sessionIdentifier else {
            completionHandler()
            return
        }
        AudiobookShelfService.shared.backgroundCompletion = completionHandler
    }
}
