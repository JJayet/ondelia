//
//  IsoraWatchWidget.swift
//  IsoraWatchWidget
//
//  Created by Jonathan Jayet on 06/09/2026.
//

import WidgetKit
import SwiftUI

struct WatchNowPlayingEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchNowPlayingSnapshot
}

struct WatchNowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchNowPlayingEntry {
        WatchNowPlayingEntry(date: Date(), snapshot: WatchNowPlayingSnapshot.read())
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchNowPlayingEntry) -> Void) {
        completion(WatchNowPlayingEntry(date: Date(), snapshot: WatchNowPlayingSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchNowPlayingEntry>) -> Void) {
        let now = Date()
        let snapshot = WatchNowPlayingSnapshot.read()
        let nowEntry = WatchNowPlayingEntry(date: now, snapshot: snapshot)

        guard snapshot.isPlaying else {
            completion(Timeline(entries: [nowEntry], policy: .never))
            return
        }

        // Second entry lands when the current chapter (or, lacking chapter bounds, the book)
        // finishes — the point the gauge/percent actually needs to change.
        let horizon = snapshot.chapterEnd.map { max($0 - snapshot.current, 0) } ?? snapshot.remainingInBook
        let endEntry = WatchNowPlayingEntry(
            date: now.addingTimeInterval(horizon),
            snapshot: snapshot.advanced(by: horizon)
        )

        let refreshDelay: TimeInterval = 5 * 60
        completion(Timeline(entries: [nowEntry, endEntry], policy: .after(now.addingTimeInterval(refreshDelay))))
    }
}

struct IsoraWatchWidget: Widget {
    let kind = "IsoraWatchNowPlaying"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchNowPlayingProvider()) { entry in
            WatchNowPlayingWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(URL(string: "isora://resume"))
        }
        .configurationDisplayName(WidgetStrings.configurationDisplayName)
        .description(WidgetStrings.configurationDescription)
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner, .accessoryInline])
    }
}

#Preview(as: .accessoryRectangular) {
    IsoraWatchWidget()
} timeline: {
    WatchNowPlayingEntry(date: .now, snapshot: WatchNowPlayingSnapshot.read())
}
