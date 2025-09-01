//
//  AudiobookReaderWidgetLiveActivity.swift
//  AudiobookReaderWidget
//
//  Created by Jonathan Jayet on 01/09/2025.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct AudiobookReaderWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct AudiobookReaderWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AudiobookReaderWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension AudiobookReaderWidgetAttributes {
    fileprivate static var preview: AudiobookReaderWidgetAttributes {
        AudiobookReaderWidgetAttributes(name: "World")
    }
}

extension AudiobookReaderWidgetAttributes.ContentState {
    fileprivate static var smiley: AudiobookReaderWidgetAttributes.ContentState {
        AudiobookReaderWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: AudiobookReaderWidgetAttributes.ContentState {
         AudiobookReaderWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: AudiobookReaderWidgetAttributes.preview) {
   AudiobookReaderWidgetLiveActivity()
} contentStates: {
    AudiobookReaderWidgetAttributes.ContentState.smiley
    AudiobookReaderWidgetAttributes.ContentState.starEyes
}
