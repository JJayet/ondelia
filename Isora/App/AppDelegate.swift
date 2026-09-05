import Intents
import UIKit

/// The one thing SwiftUI's lifecycle has no hook for: handing the system an intent handler.
///
/// `INPlayMediaIntent` is what the media suggestions replay when someone taps the app's cover
/// in Control Center, so it has to be answered in the app process where the player lives.
final class AppDelegate: NSObject, UIApplicationDelegate {
    private let mediaIntentHandler = MediaIntentHandler()

    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
        intent is INPlayMediaIntent ? mediaIntentHandler : nil
    }
}
