import SwiftUI
import WidgetKit
import ActivityKit

// MARK: - Widget Bundle Entry Point
// This is the main entry point for widgets - required for dashboard discovery
@main
struct AudiobookWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
        AudiobookLiveActivity()
    }
}
